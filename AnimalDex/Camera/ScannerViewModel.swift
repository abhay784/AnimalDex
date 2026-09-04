import SwiftUI
import CoreVideo
import ImageIO
import os

/// Drives the scanner screen: owns the frame source, the recognizer, and the gate,
/// and exposes exactly what the UI needs to render.
@MainActor
@Observable
final class ScannerViewModel {

    // MARK: - Published state

    private(set) var gateState: GateState = .idle
    private(set) var lockedSpecies: Species?
    private(set) var errorMessage: String?
    private(set) var isStarted = false

    /// Diagnostics only — the game loop never reads these.
    private(set) var lastResult: RecognitionResult?
    private(set) var framesSeen = 0

    var recognizerID: String { recognizer.identifier }

    /// Set when the shutter fires; the scanner presents the catch sequence off this.
    var pendingCatch: PendingCatch?

    // MARK: - Collaborators

    let source: any FrameSource
    private let recognizer: any SpeciesRecognizer
    private let gate = RecognitionGate()
    private let catalog: SpeciesCatalog

    /// Guards against piling up recognitions when classification is slower than
    /// the frame interval — we drop frames rather than queue them, because a
    /// backlog of stale frames is worse than a gap.
    private var isRecognizing = false

    private let log = Logger(subsystem: "com.abhay.animaldex", category: "scanner")

    init(catalog: SpeciesCatalog = .shared) {
        self.catalog = catalog
        self.recognizer = RecognizerFactory.makeDefault(catalog: catalog)
        #if targetEnvironment(simulator)
        self.source = SampleFrameSource()
        #else
        self.source = AVFrameSource()
        #endif
    }

    func start() async {
        guard !isStarted else { return }
        source.onFrame = { [weak self] input, orientation in
            self?.handleFrame(input, orientation)
        }
        do {
            try await source.start()
            isStarted = true
            errorMessage = nil
            log.info("scanner started with \(self.recognizer.identifier, privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            log.error("scanner start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        source.stop()
        isStarted = false
        gate.reset()
        gateState = .idle
        lockedSpecies = nil
    }

    /// Simulator affordance: tap the viewfinder to walk the sample set.
    func cycleSample() {
        (source as? SampleFrameSource)?.advance()
    }

    // MARK: - Frame handling

    private func handleFrame(_ input: FrameInput, _ orientation: CGImagePropertyOrientation) {
        guard !isRecognizing else { return }
        isRecognizing = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isRecognizing = false }
            do {
                let result = try await recognizer.recognize(input, orientation: orientation)
                lastResult = result
                framesSeen += 1
                let state = gate.evaluate(result)
                apply(state)
            } catch {
                log.error("recognition failed: \(error.localizedDescription)")
            }
        }
    }

    private func apply(_ state: GateState) {
        guard state != gateState else { return }
        log.debug("gate: \(String(describing: state), privacy: .public)")
        gateState = state
        lockedSpecies = state.lockedLabel.flatMap { catalog.species(forLabel: $0) }
    }

    // MARK: - Shutter

    /// Capture a full-resolution still and re-run recognition on it.
    ///
    /// The live path classifies downscaled video frames for speed; the shutter
    /// gets the good pixels. Re-running here means the entry you register is
    /// decided by the best image available, not by whatever the preview happened
    /// to be showing at the moment of the tap.
    func captureAndIdentify() async {
        do {
            let captured = try await source.captureStill()
            let result = try await recognizer.recognize(
                captured.input, orientation: captured.orientation
            )

            guard !result.isFoodContext else {
                errorMessage = "That's food, not wildlife."
                return
            }
            guard let top = result.candidates.first,
                  let species = catalog.species(forLabel: top.labelKey) else {
                errorMessage = "Couldn't identify that one. Get a little closer."
                return
            }

            pendingCatch = PendingCatch(
                species: species,
                image: captured.image,
                confidence: top.confidence,
                wasCaptive: result.isCaptive
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A successful identification awaiting the catch sequence.
struct PendingCatch: Identifiable {
    let id = UUID()
    let species: Species
    let image: UIImage
    let confidence: Float
    let wasCaptive: Bool
}
