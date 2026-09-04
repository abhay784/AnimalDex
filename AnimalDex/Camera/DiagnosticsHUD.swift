import SwiftUI

/// Whether the diagnostic overlay is showing. Persisted so it survives the
/// relaunches that happen constantly while testing on a real device.
enum Diagnostics {
    private static let key = "animaldex.showDiagnostics"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Raw recognizer output, on screen.
///
/// This exists for one job: making on-device failure *legible*. A scanner that
/// never locks looks identical whether the model returned nothing, returned a
/// creature just below threshold, returned only umbrella labels, or was vetoed
/// as food. This shows which.
struct DiagnosticsHUD: View {
    let recognizerID: String
    let gateState: GateState
    let result: RecognitionResult?
    let framesSeen: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header

            if let result {
                if result.rawTop.isEmpty {
                    row("no labels above 0.10", "", .ignored)
                } else {
                    ForEach(result.rawTop) { observation in
                        row(observation.label,
                            String(format: "%.2f", observation.confidence),
                            observation.kind)
                    }
                }

                if result.isFoodContext {
                    Text("FOOD VETO ACTIVE — catch blocked")
                        .font(Theme.display(9))
                        .foregroundStyle(Theme.ledRed)
                }
                if result.isCaptive {
                    Text("captive context (zoo/aquarium)")
                        .font(Theme.screenText(9))
                        .foregroundStyle(Theme.ledYellow)
                }
            } else {
                row("waiting for first frame…", "", .ignored)
            }
        }
        .padding(9)
        .frame(maxWidth: 260, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.lcd.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.outline, lineWidth: 2))
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recognizerID.uppercased())
                .font(Theme.display(9))
                .tracking(0.8)
                .foregroundStyle(Theme.phosphor)
            HStack(spacing: 6) {
                Text("frames \(framesSeen)")
                Text("·")
                Text(gateLabel)
                    .foregroundStyle(gateColor)
            }
            .font(Theme.screenText(9))
            .foregroundStyle(Theme.phosphor.opacity(0.7))
            Rectangle()
                .fill(Theme.phosphor.opacity(0.3))
                .frame(height: 1)
                .padding(.vertical, 2)
        }
    }

    private var gateLabel: String {
        switch gateState {
        case .idle: return "IDLE"
        case .sensing: return "SENSING"
        case .locked(let key, let confidence): return "LOCK \(key) \(String(format: "%.2f", confidence))"
        }
    }

    private var gateColor: Color {
        switch gateState {
        case .idle: return Theme.phosphor.opacity(0.6)
        case .sensing: return Theme.ledYellow
        case .locked: return Theme.ledGreen
        }
    }

    private func row(_ label: String, _ value: String, _ kind: RawObservation.Kind) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(for: kind))
                .frame(width: 6, height: 6)
            Text(label)
                .font(Theme.screenText(10))
                .foregroundStyle(Theme.phosphor)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(Theme.screenText(10))
                .foregroundStyle(Theme.phosphor.opacity(0.85))
        }
    }

    private func color(for kind: RawObservation.Kind) -> Color {
        switch kind {
        case .catchable:  return Theme.ledGreen
        case .hypernym:   return Theme.ledYellow
        case .food:       return Theme.ledRed
        case .captivity:  return Theme.lens
        case .ignored:    return Theme.phosphor.opacity(0.35)
        }
    }
}
