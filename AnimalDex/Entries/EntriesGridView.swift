import SwiftUI
import SwiftData

/// The Dex. Every catalog entry has a slot; uncaught ones stay silhouetted.
///
/// Showing all 137 slots from the start — rather than only what you've found —
/// is what makes it a collection instead of a photo album. The gaps are the game.
struct EntriesGridView: View {
    @Environment(SpeciesCatalog.self) private var catalog
    @Query(sort: \CatchRecord.capturedAt, order: .reverse) private var catches: [CatchRecord]

    @State private var filter: TaxonType?
    @State private var selected: Species?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            header
            filterBar
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(visibleSpecies) { species in
                        slot(for: species)
                    }
                }
                .padding(12)
                // The control deck floats over the scroll view, so the last row
                // needs clearance or it sits permanently half-hidden behind it.
                .padding(.bottom, 24)
            }
            .background(Theme.phosphorDim)
        }
        .background(Theme.phosphorDim)
        .sheet(item: $selected) { species in
            EntryDetailView(species: species, catches: catches(for: species))
        }
    }

    // MARK: - Derived state

    /// Species key -> number of times caught. Built once per render rather than
    /// a fetch per slot, which would be 137 queries on every scroll tick.
    private var caughtCounts: [String: Int] {
        catches.reduce(into: [:]) { $0[$1.speciesKey, default: 0] += 1 }
    }

    private var visibleSpecies: [Species] {
        guard let filter else { return catalog.all }
        return catalog.all.filter { $0.taxonType == filter }
    }

    private func catches(for species: Species) -> [CatchRecord] {
        catches.filter { $0.speciesKey == species.labelKey }
    }

    private var completion: Double {
        guard catalog.totalCount > 0 else { return 0 }
        return Double(caughtCounts.keys.count) / Double(catalog.totalCount)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Theme.outline.opacity(0.25), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: completion)
                    .stroke(Theme.ledGreen, style: .init(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(completion * 100))%")
                    .font(Theme.display(11))
                    .foregroundStyle(Theme.outline)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(format: "%03d", caughtCounts.keys.count)) / \(String(format: "%03d", catalog.totalCount))")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.outline)
                Text("SPECIES REGISTERED")
                    .font(Theme.display(9))
                    .tracking(1.4)
                    .foregroundStyle(Theme.outline.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.outline).frame(height: 3) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(label: "ALL", tint: Theme.outline, isOn: filter == nil) { filter = nil }
                ForEach(TaxonType.allCases, id: \.self) { type in
                    if !catalog.species(ofType: type).isEmpty {
                        chip(label: type.displayName, tint: type.color, isOn: filter == type) {
                            filter = filter == type ? nil : type
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.panelShadow)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.outline).frame(height: 2) }
    }

    private func chip(label: String, tint: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            SoundBank.shared.play(.select)
            action()
        } label: {
            Text(label)
                .font(Theme.display(10))
                .tracking(0.6)
                .outlinedText(isOn ? .white : tint, outline: isOn ? Theme.outline : .clear, width: isOn ? 1.2 : 0)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isOn ? tint : Theme.panel))
                .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Slot

    private func slot(for species: Species) -> some View {
        let count = caughtCounts[species.labelKey] ?? 0
        let caught = count > 0

        return Button {
            guard caught else {
                SoundBank.shared.play(.error)
                return
            }
            SoundBank.shared.play(.select)
            selected = species
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    if caught, let record = catches(for: species).first,
                       let image = PhotoStore.shared.load(record.photoFilename) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if caught {
                        Theme.phosphor
                        Image(systemName: species.taxonType.systemImage)
                            .font(.system(size: 30, weight: .black))
                            .foregroundStyle(Theme.outline.opacity(0.4))
                    } else {
                        Theme.phosphor
                        // Silhouette: the shape is visible, the identity isn't.
                        Image(systemName: species.taxonType.systemImage)
                            .font(.system(size: 30, weight: .black))
                            .foregroundStyle(Theme.outline)
                            .opacity(0.85)
                    }

                    if count > 1 {
                        Text("×\(count)")
                            .font(Theme.display(10))
                            .outlinedText()
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.outline.opacity(0.8)))
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(Scanlines().opacity(0.09))

                VStack(spacing: 1) {
                    Text(species.formattedNumber)
                        .font(Theme.display(8))
                        .foregroundStyle(Theme.outline.opacity(0.65))
                    Text(caught ? species.commonName.uppercased() : "???")
                        .font(Theme.display(9))
                        .foregroundStyle(Theme.outline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(caught ? species.rarity.color.opacity(0.35) : Theme.panelShadow)
            }
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(caught ? species.rarity.color : Theme.outline.opacity(0.4), lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
    }
}
