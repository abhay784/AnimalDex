import AVFoundation
import ImageIO
import UIKit
import os

/// Real camera. Runs the capture session off the main thread and hands throttled
/// frames back on the main actor.
@MainActor
final class AVFrameSource: NSObject, FrameSource {

    var onFrame: ((FrameInput, CGImagePropertyOrientation) -> Void)?

    private let session = AVCaptureSession()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()

    /// All session mutation happens here. Touching AVCaptureSession from the
    /// main thread stalls the UI during configuration.
    private let sessionQueue = DispatchQueue(label: "com.abhay.animaldex.session")
    nonisolated(unsafe) private let bufferQueue = DispatchQueue(label: "com.abhay.animaldex.buffers")

    /// Recognition runs at ~4fps, not 30. Classifying every frame would burn
    /// battery and the extra frames tell us nothing new at human timescales.
    private static let frameInterval: CFTimeInterval = 0.25
    nonisolated(unsafe) private var lastFrameTime: CFTimeInterval = 0

    private var stillContinuation: CheckedContinuation<CapturedImage, Error>?

    private let log = Logger(subsystem: "com.abhay.animaldex", category: "camera")

    var previewSession: AVCaptureSession? { session }

    // MARK: - Lifecycle

    func start() async throws {
        guard try await requestAccess() else { throw CameraError.permissionDenied }
        try await configureIfNeeded()
        await withCheckedContinuation { cont in
            sessionQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
                cont.resume()
            }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func requestAccess() async throws -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private var isConfigured = false

    private func configureIfNeeded() async throws {
        guard !isConfigured else { return }
        isConfigured = true

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else { throw CameraError.unavailable }

        let input = try AVCaptureDeviceInput(device: device)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                session.beginConfiguration()
                session.sessionPreset = .photo

                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    cont.resume(throwing: CameraError.unavailable)
                    return
                }
                session.addInput(input)

                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                videoOutput.setSampleBufferDelegate(self, queue: bufferQueue)
                if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

                if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

                session.commitConfiguration()
                cont.resume()
            }
        }
    }

    // MARK: - Still capture

    func captureStill() async throws -> CapturedImage {
        try await withCheckedThrowingContinuation { cont in
            self.stillContinuation = cont
            let settings = AVCapturePhotoSettings()
            sessionQueue.async { [photoOutput] in
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

// MARK: - Live frames

extension AVFrameSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= Self.frameInterval else { return }
        lastFrameTime = now

        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        Task { @MainActor [weak self] in
            // Back camera in portrait delivers landscape-right buffers.
            self?.onFrame?(.pixelBuffer(pixels), .right)
        }
    }
}

// MARK: - Photo delegate

extension AVFrameSource: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.stillContinuation = nil }

            guard error == nil,
                  let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data),
                  let cg = image.cgImage else {
                self.stillContinuation?.resume(throwing: CameraError.captureFailed)
                return
            }
            self.stillContinuation?.resume(
                returning: CapturedImage(image: image, input: .cgImage(cg), orientation: .up)
            )
        }
    }
}
