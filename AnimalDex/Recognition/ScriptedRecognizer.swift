#if targetEnvironment(simulator)
import Foundation
import ImageIO
import os

/// Simulator-only stand-in for the real classifier.
///
/// **Why this exists.** `VNClassifyImageRequest` does not work in the iOS
/// Simulator. It first fails outright (`Failed to create espresso context`,
/// because there is no Neural Engine and the emulated GPU cannot host a Core ML
/// context), and if you pin it to the CPU it does something worse: it returns a
/// *constant* result — every one of our eight sample photos classified as
/// `night_sky: 0.49` — so it looks like it is working while ignoring the input
/// entirely. The same model on the same photos classifies correctly on macOS
/// natively (butterfly 0.93, squirrel 0.99), so this is a Simulator limitation,
/// not a model or pipeline problem.
///
/// Without a substitute, nothing downstream of the viewfinder — the catch
/// sequence, registration, the dex, the map — could be exercised without a
/// physical device. This derives the answer from the sample's filename, which
/// also makes Simulator runs *deterministic*: a fixed input always produces a
/// fixed catch, which is a better basis for testing the game loop than live
/// inference would be anyway.
///
/// Device builds never compile this file; they use `VisionBuiltinRecognizer`.
final class ScriptedRecognizer: SpeciesRecognizer {

    let identifier = "scripted.simulator"

    private let catchableLabels: Set<String>
    private let log = Logger(subsystem: "com.abhay.animaldex", category: "recognition.sim")

    /// Set by `SampleFrameSource` as it advances, since a filename cannot be
    /// recovered from a decoded `CGImage`.
    nonisolated(unsafe) static var currentSampleName: String = ""

    /// Mild jitter around a high base confidence, so the gate you are building
    /// still sees a *varying* signal rather than a constant — flickering input
    /// is the whole problem `RecognitionGate` exists to solve, and a stub that
    /// returned 0.95 every frame would hide whether your smoothing works.
    private var frameCounter = 0

    init(catalog: SpeciesCatalog = .shared) {
        self.catchableLabels = Set(catalog.all.map(\.labelKey))
    }

    func recognize(
        _ input: FrameInput,
        orientation: CGImagePropertyOrientation
    ) async throws -> RecognitionResult {
        let name = Self.currentSampleName
        guard catchableLabels.contains(name) else {
            log.warning("sample '\(name, privacy: .public)' is not a catalog label")
            return .empty
        }

        frameCounter += 1
        // Deterministic pseudo-jitter in roughly 0.42...0.92 — occasionally dips
        // below a naive 0.5 threshold, which is exactly the flicker the gate
        // needs to absorb.
        let wobble = [0.92, 0.71, 0.44, 0.88, 0.63, 0.79, 0.42, 0.85][frameCounter % 8]

        return RecognitionResult(
            candidates: [.init(labelKey: name, confidence: Float(wobble))],
            hypernyms: [],
            isFoodContext: false,
            isCaptive: false
        )
    }
}
#endif
