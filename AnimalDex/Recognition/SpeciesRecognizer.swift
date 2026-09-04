import CoreVideo
import ImageIO

/// One label the recognizer believes it saw.
struct RecognitionCandidate: Hashable, Sendable {
    let labelKey: String
    let confidence: Float
}

/// One raw label as the model reported it, plus how we interpreted it.
///
/// Exists purely for on-device diagnosis. Without it, a scanner that never locks
/// is indistinguishable between "the model saw nothing", "it saw a creature but
/// below threshold", "it only produced umbrella labels", and "the food veto
/// fired" — four different bugs presenting as one blank screen.
struct RawObservation: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable {
        case catchable    // resolves to a dex entry
        case hypernym     // umbrella label, gates but never catches
        case food         // veto trigger
        case captivity    // zoo / aquarium context
        case ignored      // not a creature label at all
    }

    let label: String
    let confidence: Float
    let kind: Kind

    var id: String { label }
}

/// A single frame's interpretation, already sorted into meaningful buckets so
/// callers never have to know how the underlying model labels things.
struct RecognitionResult: Sendable {
    /// Catchable species, highest confidence first. Resolved against the catalog.
    let candidates: [RecognitionCandidate]

    /// Umbrella hits (`bird`, `mammal`) with no specific species behind them.
    let hypernyms: [RecognitionCandidate]

    /// A food-context label fired — this is a meal, not a creature.
    let isFoodContext: Bool

    /// Zoo / aquarium / terrarium context. Recorded, not blocked.
    let isCaptive: Bool

    /// Highest-confidence raw labels, for the diagnostic overlay only. Nothing
    /// in the game loop reads this.
    let rawTop: [RawObservation]

    static let empty = RecognitionResult(
        candidates: [], hypernyms: [], isFoodContext: false, isCaptive: false, rawTop: []
    )
}

/// The swappable brain.
///
/// Track A ships `VisionBuiltinRecognizer` (Apple's on-device classifier, ~137
/// catchable labels, zero model file). Track B will ship `CoreMLSpeciesRecognizer`
/// backed by a MobileNetV3 fine-tuned on iNaturalist. Because both conform to
/// this, swapping them is a one-line change in `RecognizerFactory` and nothing
/// upstream of it needs to know.
protocol SpeciesRecognizer: Sendable {
    /// Shown in debug UI so it's always obvious which brain is running.
    var identifier: String { get }

    func recognize(
        _ input: FrameInput,
        orientation: CGImagePropertyOrientation
    ) async throws -> RecognitionResult
}

/// Single place the active recognizer is chosen.
enum RecognizerFactory {
    static func makeDefault(catalog: SpeciesCatalog = .shared) -> any SpeciesRecognizer {
        #if targetEnvironment(simulator)
        // VNClassifyImageRequest is non-functional in the Simulator - see the
        // header of ScriptedRecognizer for the full diagnosis.
        ScriptedRecognizer(catalog: catalog)
        #else
        // Track B swap point: return CoreMLSpeciesRecognizer(catalog: catalog)
        VisionBuiltinRecognizer(catalog: catalog)
        #endif
    }
}
