import SwiftUI

/// Cold-start sequence: the orb spins up, then the device unhinges to reveal the app.
///
/// Everything is driven off one `Phase` enum rather than a pile of independent
/// booleans, so the audio cues and the animation share a single clock. Getting
/// a hinge sound to land on the hinge is otherwise a guessing game.
struct BootSequenceView: View {
    var onFinish: () -> Void

    private enum Phase: Int, Comparable {
        case dark, spinning, unlatch, opening, done
        static func < (l: Phase, r: Phase) -> Bool { l.rawValue < r.rawValue }
    }

    @State private var phase: Phase = .dark
    @State private var hingeAngle: Double = 0
    @State private var titleOpacity: Double = 0

    var body: some View {
        ZStack {
            Theme.outline.ignoresSafeArea()

            VStack(spacing: 26) {
                OrbMark(size: 108, isSpinning: phase == .spinning)
                    .scaleEffect(phase >= .unlatch ? 1.12 : 1.0)
                    .shadow(color: Theme.shell.opacity(0.55), radius: phase >= .unlatch ? 26 : 8)

                VStack(spacing: 4) {
                    Text("ANIMALDEX")
                        .font(Theme.display(34))
                        .tracking(3)
                        .outlinedText(Theme.panel)
                    Text("FIELD RESEARCH UNIT")
                        .font(Theme.screenText(10))
                        .tracking(2)
                        .foregroundStyle(Theme.phosphor)
                }
                .opacity(titleOpacity)
            }

            // The clamshell: two crimson halves that swing away from the middle.
            VStack(spacing: 0) {
                shellHalf(isTop: true)
                shellHalf(isTop: false)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .task { await run() }
    }

    private func shellHalf(isTop: Bool) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: isTop
                        ? [Theme.shellHighlight, Theme.shell]
                        : [Theme.shell, Theme.shellShadow],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(alignment: isTop ? .bottom : .top) {
                Rectangle().fill(Theme.outline).frame(height: 4)
            }
            .rotation3DEffect(
                .degrees(isTop ? -hingeAngle : hingeAngle),
                axis: (x: 1, y: 0, z: 0),
                anchor: isTop ? .top : .bottom,
                perspective: 0.55
            )
    }

    private func run() async {
        phase = .spinning
        SoundBank.shared.play(.orbSpin)
        withAnimation(.easeOut(duration: 0.5).delay(0.25)) { titleOpacity = 1 }

        try? await Task.sleep(for: .milliseconds(1150))
        phase = .unlatch
        Haptics.hinge()
        SoundBank.shared.play(.dexOpen)

        try? await Task.sleep(for: .milliseconds(220))
        phase = .opening
        withAnimation(.timingCurve(0.7, 0.0, 0.2, 1.0, duration: 0.75)) {
            hingeAngle = 92
        }

        try? await Task.sleep(for: .milliseconds(820))
        phase = .done
        withAnimation(.easeInOut(duration: 0.25)) { onFinish() }
    }
}
