import SwiftUI

/// The registered-entry card. Used by the catch reveal and the entry detail
/// screen, so a creature looks identical the moment you catch it and forever after.
struct DexCardView: View {
    let species: Species
    var image: UIImage?
    /// Reveals the description with a typewriter effect during the catch reveal.
    var revealedCharacters: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            photoWindow
            details
        }
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(frameStyle, lineWidth: 5)
        }
        .overlay {
            if species.rarity.usesHolographicFoil { foil }
        }
        .shadow(color: species.rarity.color.opacity(0.55), radius: 18)
    }

    // MARK: - Rarity frame

    private var frameStyle: AnyShapeStyle {
        if species.rarity.usesGradientFrame {
            return AnyShapeStyle(
                AngularGradient(
                    colors: [species.rarity.color, .white, species.rarity.color,
                             species.rarity.color.opacity(0.6), species.rarity.color],
                    center: .center
                )
            )
        }
        return AnyShapeStyle(species.rarity.color)
    }

    /// Legendary-only: a moving prismatic wash over the whole card.
    private var foil: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .cyan.opacity(0.25),
                             .pink.opacity(0.25), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Text(species.formattedNumber)
                .font(Theme.display(14))
                .outlinedText()
            Text(species.commonName.uppercased())
                .font(Theme.display(16))
                .tracking(0.6)
                .outlinedText()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(species.rarity.color)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.outline).frame(height: 3)
        }
    }

    private var photoWindow: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.phosphor
                Image(systemName: species.taxonType.systemImage)
                    .font(.system(size: 54, weight: .black))
                    .foregroundStyle(Theme.outline.opacity(0.35))
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(Scanlines().opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.outline).frame(height: 3)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                TypeBadge(type: species.taxonType)
                RarityChip(rarity: species.rarity)
                Spacer(minLength: 0)
            }

            Text(species.scientificName)
                .font(.system(size: 12, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(Theme.outline.opacity(0.7))

            Text(displayedDescription)
                .font(Theme.screenText(11))
                .foregroundStyle(Theme.phosphor)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .frame(minHeight: 92, alignment: .topLeading)
                .screenSurface(Theme.lcd, radius: 8)

            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill").font(.system(size: 9, weight: .bold))
                Text("\(species.observationsCount.formatted()) SIGHTINGS WORLDWIDE")
                    .font(Theme.display(9))
                    .tracking(0.5)
            }
            .foregroundStyle(Theme.outline.opacity(0.55))
        }
        .padding(12)
    }

    private var displayedDescription: String {
        let full = species.dexDescription.isEmpty
            ? "No field notes recorded for this species yet."
            : species.dexDescription
        guard let count = revealedCharacters else { return full }
        return String(full.prefix(count))
    }
}
