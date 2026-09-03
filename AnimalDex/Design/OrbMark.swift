import SwiftUI

/// The AnimalDex orb — app mark, loading spinner, and shutter button.
///
/// Deliberately *not* a Poké Ball: the band is a double stripe with a notch, the
/// hemispheres are crimson-over-bone rather than red-over-white, and the center
/// carries a paw glyph. It reads as the same genre without borrowing the mark.
struct OrbMark: View {
    var size: CGFloat = 64
    var isSpinning: Bool = false
    /// Tints the lower hemisphere — used to color the shutter by rarity.
    var accent: Color = Theme.panel

    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            // Upper / lower hemispheres
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.shellHighlight, Theme.shell, Theme.shellShadow],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .mask(alignment: .top) {
                    Rectangle().frame(height: size / 2)
                }
            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: size / 2)
                }

            // Double-stripe equator with a notch on the right
            Rectangle()
                .fill(Theme.outline)
                .frame(height: size * 0.13)
            Rectangle()
                .fill(accent.opacity(0.9))
                .frame(width: size * 0.16, height: size * 0.05)
                .offset(x: size * 0.3)

            // Center button
            Circle()
                .fill(Theme.panel)
                .frame(width: size * 0.34)
                .overlay(Circle().strokeBorder(Theme.outline, lineWidth: size * 0.045))
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.15, weight: .black))
                .foregroundStyle(Theme.outline)

            // Specular highlight sells the plastic
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.55), .clear],
                        center: .init(x: 0.32, y: 0.26),
                        startRadius: 0, endRadius: size * 0.42
                    )
                )
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.outline, lineWidth: max(2, size * 0.055)))
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
        .onAppear { if isSpinning { spin() } }
        .onChange(of: isSpinning) { _, now in if now { spin() } }
    }

    private func spin() {
        withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }
}

/// Three status LEDs, as on the device's lens cluster. The green one pulses when
/// the scanner has a lock, which gives the chrome something to *say*.
struct StatusLEDs: View {
    var active: Bool = false
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: size * 0.55) {
            led(Theme.ledRed, lit: true)
            led(Theme.ledYellow, lit: !active)
            led(Theme.ledGreen, lit: active)
        }
    }

    private func led(_ color: Color, lit: Bool) -> some View {
        Circle()
            .fill(lit ? color : color.opacity(0.28))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(.white.opacity(lit ? 0.7 : 0.2))
                    .frame(width: size * 0.3, height: size * 0.3)
                    .offset(x: size * 0.2, y: size * 0.18)
            }
            .shadow(color: lit ? color.opacity(0.8) : .clear, radius: 3)
    }
}

/// The big blue lens on the upper-left of the chrome.
struct DexLens: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(Theme.panel)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.lens.opacity(0.75), Theme.lens, Color(hex: 0x14456F)],
                        center: .init(x: 0.4, y: 0.35),
                        startRadius: 1, endRadius: size * 0.6
                    )
                )
                .padding(size * 0.11)
            // Crescent glint
            Circle()
                .trim(from: 0.55, to: 0.78)
                .stroke(Theme.lensGlint, style: .init(lineWidth: size * 0.09, lineCap: .round))
                .padding(size * 0.22)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 2.5))
    }
}
