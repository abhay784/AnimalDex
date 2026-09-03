import AVFoundation
import ImageIO
import UIKit
import os

/// Stand-in camera for the Simulator, which has no capture hardware.
///
/// Cycles through real photographs bundled in `Resources/dev_samples/`. They are
/// real animal photos on purpose: synthetic shapes would sail through the UI but
/// tell us nothing about whether recognition actually works, and recognition is
/// the part most worth exercising.
@MainActor
final class SampleFrameSource: FrameSource {

    var onFrame: ((FrameInput, CGImagePropertyOrientation) -> Void)?
    var previewSession: AVCaptureSession? { nil }

    /// The image currently "in view" — the preview renders this directly.
    private(set) var currentImage: UIImage?
    private(set) var currentName: String = ""

    private var samples: [(name: String, image: UIImage)] = []
    private var index = 0
    private var timer: Timer?

    private let log = Logger(subsystem: "com.abhay.animaldex", category: "camera.sim")

    init() {
        loadSamples()
    }

    private func loadSamples() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: nil) ?? []
        samples = urls
            .filter { $0.lastPathComponent.hasPrefix("sample_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "sample_", with: "")
                return (name, image)
            }
        currentImage = samples.first?.image
        currentName = samples.first?.name ?? ""
        ScriptedRecognizer.currentSampleName = currentName
        if samples.isEmpty {
            log.warning("No sample_*.jpg in bundle — run tools/fetch_samples.py")
        }
    }

    func start() async throws {
        log.info("start(): samples=\(self.samples.count) onFrame=\(self.onFrame != nil)")
        guard !samples.isEmpty else { throw CameraError.unavailable }
        emit()
        // Same ~4fps cadence as the real source, so the gate sees a comparable
        // stream and its smoothing behaves the same in both environments.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emit() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Advance to the next bundled photo. Wired to a tap on the preview so you
    /// can walk the whole sample set by hand while testing.
    func advance() {
        guard !samples.isEmpty else { return }
        index = (index + 1) % samples.count
        currentImage = samples[index].image
        currentName = samples[index].name
        ScriptedRecognizer.currentSampleName = currentName
        emit()
    }

    private func emit() {
        guard let image = currentImage else {
            log.error("emit: no currentImage")
            return
        }
        guard let cg = image.cgImage else {
            log.error("emit: sample has no CGImage")
            return
        }
        guard let onFrame else {
            log.error("emit: onFrame not wired")
            return
        }
        onFrame(.cgImage(cg), .up)
    }

    func captureStill() async throws -> CapturedImage {
        guard let image = currentImage, let cg = image.cgImage else {
            throw CameraError.captureFailed
        }
        return CapturedImage(image: image, input: .cgImage(cg), orientation: .up)
    }
}
