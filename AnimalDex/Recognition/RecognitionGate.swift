import Foundation

/// What the scanner UI should currently be showing.
enum GateState: Equatable, Sendable {
    /// Nothing of interest in frame.
    case idle

    /// A creature is present but unidentified — an umbrella label fired with no
    /// species behind it. Drives the "get closer" prompt.
    case sensing

    /// A stable, catchable identification. The shutter is armed.
    case locked(labelKey: String, confidence: Float)

    var lockedLabel: String? {
        if case .locked(let key, _) = self { return key }
        return nil
    }
}

/// Smooths per-frame recognition into a stable UI state.
///
/// Live classification output is *noisy*. Pointed at a stationary squirrel, the
/// Vision classifier will happily return 0.71, 0.44, 0.68, 0.31, 0.77 across five
/// consecutive frames. Feeding that straight into a threshold makes the "A wild
/// ___ appeared!" banner strobe on and off several times a second, which reads as
/// a broken app rather than a hesitant one.
///
/// This type owns the fix. It is fed every frame's result and returns the state
/// the UI should actually render.
@Observable
final class RecognitionGate {

    /// How many recent frames to retain. At the ~4fps capture rate this is
    /// roughly a 1.5 second window.
    static let historyDepth = 6

    /// Most-recent-last ring of observations. Already maintained for you.
    private(set) var history: [RecognitionResult] = []

    private(set) var state: GateState = .idle

    /// Feed one frame. Returns the state the scanner should render.
    @discardableResult
    func evaluate(_ result: RecognitionResult) -> GateState {
        history.append(result)
        if history.count > Self.historyDepth {
            history.removeFirst(history.count - Self.historyDepth)
        }

        // Food context is an immediate, unconditional veto — no smoothing needed,
        // because a plate of salmon does not become a fish if you look longer.
        if result.isFoodContext {
            state = .idle
            return state
        }

        state = decide(from: history)
        return state
    }

    func reset() {
        history.removeAll()
        state = .idle
    }

    /// Decides the gate state from the recent frame window.
    ///
    /// - Parameter window: Up to `historyDepth` recent results, oldest first.
    ///   `window.last` is the current frame.
    /// - Returns: What the scanner should display.
    ///
    /// ## Why this is yours to decide
    ///
    /// This function alone determines whether the camera feels magic or broken.
    /// Everything else in the recognition path is plumbing; this is the judgment.
    ///
    /// ## Approaches worth weighing
    ///
    /// - **N-of-M agreement.** Require the same `labelKey` to appear in at least
    ///   N of the last M frames before locking. Very stable, but adds latency
    ///   proportional to N — you will miss a bird that lands for half a second.
    /// - **Exponential moving average.** Keep a decaying score per label and lock
    ///   when it crosses a threshold. Smooth and responsive, but a single very
    ///   confident frame can trip it.
    /// - **Hysteresis.** Two thresholds instead of one: lock at 0.70, but do not
    ///   *un*lock until confidence drops below 0.40. Cheap, and specifically
    ///   kills the flicker without adding lock latency. Composes well with either
    ///   of the above.
    ///
    /// ## The trade-off
    ///
    /// A tight gate means the banner is trustworthy — when it fires, there really
    /// is a squirrel — but you will lose fast-moving subjects, and birds are the
    /// entire point of a nature app. A loose gate catches the fleeting stuff but
    /// cries wolf, and a game that announces creatures that aren't there stops
    /// being believable fast.
    ///
    /// Also yours: when to return `.sensing`. `window.last?.hypernyms` being
    /// non-empty with no candidates means "something's there, I can't name it."
    /// You could surface that immediately (responsive, encourages moving closer)
    /// or require the same stability treatment as a lock (calmer, fewer prompts).
    ///
    /// Roughly 10 lines. Replace the placeholder below.
    private func decide(from window: [RecognitionResult]) -> GateState {
        // TODO: (yours) Smooth `window` into a GateState. See the discussion above.
        //
        // Placeholder so the loop runs end-to-end: naive single-frame threshold,
        // no smoothing at all. This is precisely the strobing behavior described
        // above — point the camera at a creature and watch the banner flicker.
        // That flicker is the thing you are fixing.
        guard let current = window.last else { return .idle }

        if let top = current.candidates.first, top.confidence >= 0.5 {
            return .locked(labelKey: top.labelKey, confidence: top.confidence)
        }
        if !current.hypernyms.isEmpty {
            return .sensing
        }
        return .idle
    }
}
