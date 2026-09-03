import AVFoundation
import CoreVideo
import ImageIO
import UIKit
import Vision

/// A frame to classify.
///
/// Two cases rather than one, because the two sources genuinely differ: the
/// camera hands us `CVPixelBuffer`s that Vision consumes with no copy, while the
/// Simulator's sample source already holds a decoded image. Forcing the sample
/// path through a hand-rolled `UIImage -> CVPixelBuffer` conversion was both
/// wasted work and, for a while, silently producing black buffers — Vision
/// dutifully classified them as `night_sky`.
enum FrameInput: @unchecked Sendable {
    case pixelBuffer(CVPixelBuffer)
    case cgImage(CGImage)

    func makeHandler(orientation: CGImagePropertyOrientation) -> VNImageRequestHandler {
        switch self {
        case .pixelBuffer(let buffer):
            VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
        case .cgImage(let image):
            VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        }
    }
}

/// A still captured by the shutter: what the recognizer judges, plus what we keep.
struct CapturedImage: @unchecked Sendable {
    let image: UIImage
    let input: FrameInput
    let orientation: CGImagePropertyOrientation
}

/// Where live frames come from.
///
/// This exists because **the iOS Simulator has no camera**. Without a seam here,
/// every feature downstream of the viewfinder — recognition, the catch sequence,
/// the dex, the map — would be untestable until running on a physical device.
@MainActor
protocol FrameSource: AnyObject {
    /// Fired on the main actor, already throttled to the recognition rate.
    var onFrame: ((FrameInput, CGImagePropertyOrientation) -> Void)? { get set }

    /// The session to attach a preview layer to, if this source has one.
    var previewSession: AVCaptureSession? { get }

    func start() async throws
    func stop()
    func captureStill() async throws -> CapturedImage
}

enum CameraError: LocalizedError {
    case permissionDenied
    case unavailable
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "AnimalDex needs camera access to spot creatures."
        case .unavailable:      return "No usable camera on this device."
        case .captureFailed:    return "That shot didn't come through. Try again."
        }
    }
}
