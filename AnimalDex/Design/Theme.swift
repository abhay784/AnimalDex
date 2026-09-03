import SwiftUI

/// The AnimalDex visual language: injection-molded plastic, saturated primaries,
/// heavy outlines. Nothing here should read as a default iOS control.
enum Theme {

    // MARK: - Palette

    /// Device shell.
    static let shell          = Color(hex: 0xD8232A)
    static let shellShadow    = Color(hex: 0xA81419)
    static let shellHighlight = Color(hex: 0xF2555B)

    /// The big lens on the upper-left of the chrome.
    static let lens           = Color(hex: 0x2B7FD4)
    static let lensGlint      = Color.white.opacity(0.85)

    /// Status LEDs beside the lens.
    static let ledRed         = Color(hex: 0xE8402A)
    static let ledYellow      = Color(hex: 0xF2C438)
    static let ledGreen       = Color(hex: 0x4CBB4C)

    /// Screens. Phosphor is the "list" surface; LCD is the "detail" surface.
    static let phosphor       = Color(hex: 0x9BBC5A)
    static let phosphorDim    = Color(hex: 0x7C9B45)
    static let lcd            = Color(hex: 0x0E2A47)
    static let lcdDim         = Color(hex: 0x0A1E33)

    /// Structural.
    static let outline        = Color(hex: 0x1A1A1A)
    static let panel          = Color(hex: 0xF5F1E6)
    static let panelShadow    = Color(hex: 0xD6D0BE)

    // MARK: - Metrics

    static let outlineWidth: CGFloat = 3
    static let bevelDepth: CGFloat = 4
    static let cornerRadius: CGFloat = 14

    // MARK: - Type

    /// Chunky display face for headings, numbers, buttons.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Compact face for screen readouts and entry body text.
    static func screenText(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Entry numbers always render as `No. 042`.
    static func entryNumber(_ n: Int) -> String {
        String(format: "No. %03d", n)
    }
}

// MARK: - Bevelled surfaces

/// A moulded plastic panel: light top edge, dark bottom edge, hard outline.
struct BevelPanel: ViewModifier {
    var fill: Color
    var radius: CGFloat = Theme.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(fill)
                    // Bottom-inner shadow and top-inner highlight sell the moulding.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .clear, .black.opacity(0.35)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: Theme.bevelDepth
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: Theme.outlineWidth)
            )
    }
}

/// An inset screen: recessed, glass reflection sweep, faint scanlines.
struct ScreenSurface: ViewModifier {
    var tint: Color
    var radius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(tint)
            .overlay(Scanlines().opacity(0.10))
            .overlay(GlassSweep().opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: Theme.outlineWidth)
            )
            // Recessed, so the shadow falls *inward* from the top.
            .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
    }
}

/// Horizontal CRT scanlines, drawn once and tiled by the renderer.
struct Scanlines: View {
    var spacing: CGFloat = 3

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black)
                )
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// A diagonal specular sweep, as if light were catching the screen glass.
struct GlassSweep: View {
    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.white.opacity(0.0), .white, .white.opacity(0.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: geo.size.width * 1.6, height: geo.size.height * 0.5)
            .rotationEffect(.degrees(-24))
            .offset(x: -geo.size.width * 0.15, y: -geo.size.height * 0.1)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func bevelPanel(_ fill: Color = Theme.panel, radius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(BevelPanel(fill: fill, radius: radius))
    }

    func screenSurface(_ tint: Color = Theme.phosphor, radius: CGFloat = 10) -> some View {
        modifier(ScreenSurface(tint: tint, radius: radius))
    }

    /// White fill, hard dark outline, 1px drop shadow — the display-type treatment.
    func outlinedText(_ color: Color = .white, outline: Color = Theme.outline, width: CGFloat = 1.6) -> some View {
        self
            .foregroundStyle(color)
            .shadow(color: outline, radius: 0, x: width, y: 0)
            .shadow(color: outline, radius: 0, x: -width, y: 0)
            .shadow(color: outline, radius: 0, x: 0, y: width)
            .shadow(color: outline, radius: 0, x: 0, y: -width)
            .shadow(color: .black.opacity(0.4), radius: 0, x: 1, y: 2)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}
