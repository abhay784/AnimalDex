import SwiftUI
import SwiftData

/// Trainer card and stats.
///
/// Friends land here once the Rust backend is up; until then this is the
/// single-player half, which is fully useful on its own.
struct ProfileView: View {
    @Environment(SpeciesCatalog.self) private var catalog
    @Query private var catches: [CatchRecord]
    @State private var location = LocationProvider()

    private var uniqueKeys: Set<String> { Set(catches.map(\.speciesKey)) }

    private var rarest: Species? {
        uniqueKeys
            .compactMap { catalog.species(forLabel: $0) }
            .max { $0.rarity < $1.rarity }
    }

    private var typeCounts: [(TaxonType, Int, Int)] {
        TaxonType.allCases.compactMap { type in
            let total = catalog.species(ofType: type).count
            guard total > 0 else { return nil }
            let found = uniqueKeys.compactMap { catalog.species(forLabel: $0) }
                .filter { $0.taxonType == type }.count
            return (type, found, total)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                trainerCard
                locationOptIn
                typeBreakdown
                friendsPlaceholder
            }
            .padding(16)
        }
        .background(Theme.phosphorDim)
    }

    /// Location is opted into here, not demanded at launch. Asking in context —
    /// next to an explanation of what it buys you — is both more respectful and
    /// more likely to get a yes than a cold prompt on first open.
    @ViewBuilder
    private var locationOptIn: some View {
        if location.authorization == .notDetermined || location.authorization == .denied {
            VStack(spacing: 9) {
                Text("PIN YOUR SIGHTINGS")
                    .font(Theme.display(12))
                    .tracking(1.2)
                    .foregroundStyle(Theme.outline)
                Text("Catches can record where you found them so they appear on your map. Locations never leave your device unless you share a catch.")
                    .font(Theme.screenText(10))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.outline.opacity(0.7))

                if location.authorization == .denied {
                    Text("ENABLE IN SETTINGS › ANIMALDEX")
                        .font(Theme.display(10))
                        .foregroundStyle(Theme.outline.opacity(0.6))
                } else {
                    Button {
                        SoundBank.shared.play(.select)
                        location.requestAuthorization()
                    } label: {
                        Text("ENABLE LOCATION")
                            .font(Theme.display(12))
                            .tracking(1.2)
                            .outlinedText()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.lens))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.outline, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .bevelPanel()
        }
    }

    private var trainerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                OrbMark(size: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("FIELD RESEARCHER")
                        .font(Theme.display(9))
                        .tracking(1.6)
                        .foregroundStyle(Theme.outline.opacity(0.6))
                    Text("TRAINER")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.outline)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                stat("\(uniqueKeys.count)", "SPECIES")
                stat("\(catches.count)", "CATCHES")
                stat(rarest?.rarity.displayName ?? "—", "BEST")
            }

            if let rarest {
                HStack(spacing: 8) {
                    Text("RAREST FIND")
                        .font(Theme.display(9))
                        .tracking(1.2)
                        .foregroundStyle(Theme.outline.opacity(0.6))
                    Spacer()
                    Text(rarest.commonName.uppercased())
                        .font(Theme.display(11))
                        .foregroundStyle(Theme.outline)
                    RarityChip(rarity: rarest.rarity, compact: true)
                }
            }
        }
        .padding(14)
        .bevelPanel()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.display(19))
                .foregroundStyle(Theme.outline)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(Theme.display(8))
                .tracking(1)
                .foregroundStyle(Theme.outline.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelShadow))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.outline, lineWidth: 2))
    }

    private var typeBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY TYPE")
                .font(Theme.display(11))
                .tracking(1.4)
                .foregroundStyle(Theme.outline.opacity(0.7))

            ForEach(typeCounts, id: \.0) { type, found, total in
                HStack(spacing: 10) {
                    TypeBadge(type: type, compact: true).frame(width: 104, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.panelShadow)
                            Capsule().fill(type.color)
                                .frame(width: geo.size.width * (total > 0 ? Double(found) / Double(total) : 0))
                        }
                    }
                    .frame(height: 12)
                    .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 2))
                    Text("\(found)/\(total)")
                        .font(Theme.display(10))
                        .foregroundStyle(Theme.outline)
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .bevelPanel()
    }

    private var friendsPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(Theme.phosphor)
            Text("FRIENDS COMING ONLINE")
                .font(Theme.display(12))
                .tracking(1.2)
                .foregroundStyle(Theme.phosphor)
            Text("Compare dexes and see friends' sightings\nonce the AnimalDex server is connected.")
                .font(Theme.screenText(10))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.phosphor.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .screenSurface(Theme.lcd, radius: 12)
    }
}
