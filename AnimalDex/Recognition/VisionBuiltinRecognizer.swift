import Vision
import CoreML
import CoreVideo
import ImageIO
import os

/// Track A's brain: Apple's built-in on-device image classifier.
///
/// `VNClassifyImageRequest` ships 1,303 labels inside the OS — no model file, no
/// download, no conversion step. Roughly 137 of those are creatures we can build
/// a dex from. It is genus-level at best (`sparrow`, not `House Sparrow`), which
/// is why Track B exists, but it makes the entire game loop real today.
final class VisionBuiltinRecognizer: SpeciesRecognizer {

    let identifier = "vision.builtin.v1"

    /// Captured at init as an immutable value rather than holding the catalog,
    /// so the recognizer stays trivially sendable across the capture queue.
    private let catchableLabels: Set<String>

    /// Floor below which we don't even consider a label. Anything under this is
    /// noise at 4fps.
    private let minimumConfidence: Float = 0.10

    private let log = Logger(subsystem: "com.abhay.animaldex", category: "recognition")

    init(catalog: SpeciesCatalog = .shared) {
        // Debug subjects (e.g. "adult", for testing against a person) resolve
        // through the same catalog lookup as a real species, so they need to be
        // catchable here too, even though they are excluded from catalog.all.
        self.catchableLabels = Set(catalog.all.map(\.labelKey))
            .union(SpeciesCatalog.debugSubjects.keys)
        if catchableLabels.isEmpty {
            log.warning("Catalog empty — recognizer will never produce a catchable candidate.")
        }
    }

    func recognize(
        _ input: FrameInput,
        orientation: CGImagePropertyOrientation
    ) async throws -> RecognitionResult {
        let request = VNClassifyImageRequest()
        pinToCPUInSimulator(request)
        try input.makeHandler(orientation: orientation).perform([request])

        guard let observations = request.results else {
            log.debug("no observations returned")
            return .empty
        }
        let result = classify(observations)
        log.debug("""
            obs=\(observations.count)             top=\(observations.prefix(4).map { "\($0.identifier):\(String(format: "%.2f", $0.confidence))" }.joined(separator: ","), privacy: .public)             catchable=\(result.candidates.count) hyper=\(result.hypernyms.count) food=\(result.isFoodContext)
            """)
        return result
    }

    /// The Simulator has no Neural Engine, and its emulated GPU routinely fails to
    /// stand up a Core ML ("espresso") inference context — every request then dies
    /// with `Failed to create espresso context` and the scanner silently never
    /// locks onto anything. Pinning inference to the CPU is slower but actually
    /// runs. Real devices keep the default, which uses the ANE.
    private func pinToCPUInSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
        guard let stages = try? request.supportedComputeStageDevices,
              let devices = stages[.main],
              let cpu = devices.first(where: { if case .cpu = $0 { return true } else { return false } })
        else {
            log.warning("No CPU compute device offered; classification will likely fail in the Simulator.")
            return
        }
        request.setComputeDevice(cpu, for: .main)
        #endif
    }

    /// Split raw observations into the buckets `RecognitionResult` promises.
    /// Separated from `recognize` so it can be unit-tested without a camera.
    func classify(_ observations: [VNClassificationObservation]) -> RecognitionResult {
        var candidates: [RecognitionCandidate] = []
        var hypernyms: [RecognitionCandidate] = []
        var raw: [RawObservation] = []
        var isFood = false
        var isCaptive = false

        for obs in observations where obs.confidence >= minimumConfidence {
            let id = obs.identifier

            // Food veto uses its own, lower threshold: a false veto costs one
            // retry, a false catch pollutes the dex permanently.
            if CreatureLabels.foodContext.contains(id),
               obs.confidence >= CreatureLabels.foodVetoThreshold {
                isFood = true
                raw.append(.init(label: id, confidence: obs.confidence, kind: .food))
                continue
            }

            if CreatureLabels.captivityContext.contains(id) {
                isCaptive = true
                raw.append(.init(label: id, confidence: obs.confidence, kind: .captivity))
                continue
            }

            // Catchable is *defined* as "present in the catalog" — there is no
            // separate allowlist to drift out of sync with it.
            if catchableLabels.contains(id) {
                candidates.append(.init(labelKey: id, confidence: obs.confidence))
                raw.append(.init(label: id, confidence: obs.confidence, kind: .catchable))
            } else if CreatureLabels.hypernyms.contains(id) {
                hypernyms.append(.init(labelKey: id, confidence: obs.confidence))
                raw.append(.init(label: id, confidence: obs.confidence, kind: .hypernym))
            } else {
                raw.append(.init(label: id, confidence: obs.confidence, kind: .ignored))
            }
        }

        candidates.sort { $0.confidence > $1.confidence }
        hypernyms.sort { $0.confidence > $1.confidence }
        raw.sort { $0.confidence > $1.confidence }

        return RecognitionResult(
            candidates: candidates,
            hypernyms: hypernyms,
            isFoodContext: isFood,
            isCaptive: isCaptive,
            rawTop: Array(raw.prefix(8))
        )
    }
}
