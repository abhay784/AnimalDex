import SwiftUI

/// The persistent device frame. A top cowl carrying the lens and status LEDs, and
/// a bottom control deck that doubles as the tab bar.
///
/// Wrapping every tab in the same chrome is what makes the app read as one
/// physical object instead of four unrelated screens — which is most of the
/// difference between "themed" and "in-world".
struct DexChromeView<Content: View>: View {
    let title: String
    var isActive: Bool = false
    @Binding var tab: RootTab
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            cowl
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.outline)
            controlDeck
        }
        .background(Theme.shell)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Top cowl

    private var cowl: some View {
        HStack(spacing: 12) {
            DexLens(size: 42)
            StatusLEDs(active: isActive)

            Spacer(minLength: 4)

            Text(title)
                .font(Theme.display(15))
                .tracking(1.6)
                .outlinedText(Theme.panel)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [Theme.shellHighlight, Theme.shell],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.outline).frame(height: 3)
        }
    }

    // MARK: - Bottom control deck

    private var controlDeck: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases) { item in
                deckButton(item)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(
            LinearGradient(
                colors: [Theme.shell, Theme.shellShadow],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.outline).frame(height: 3)
        }
    }

    private func deckButton(_ item: RootTab) -> some View {
        let selected = tab == item
        return Button {
            guard tab != item else { return }
            tab = item
            SoundBank.shared.play(.select)
            Haptics.tick()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .black))
                Text(item.label)
                    .font(Theme.display(9))
                    .tracking(0.8)
            }
            .outlinedText(selected ? Theme.outline : Theme.panel, outline: selected ? Theme.panel : Theme.outline, width: 1.2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Theme.panel : Theme.shellShadow.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.outline, lineWidth: 2.5)
            )
            // Selected reads as pressed-in rather than raised.
            .offset(y: selected ? 2 : 0)
            .shadow(color: .black.opacity(selected ? 0 : 0.35), radius: 0, x: 0, y: selected ? 0 : 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
        .accessibilityIdentifier("tab.\(item.rawValue)")
    }
}
