import Foundation

/// In-memory index over the bundled species catalog.
///
/// Loaded once at launch. Small enough (~137 entries) that holding it all in
/// memory is cheaper than any form of on-demand loading.
@Observable
final class SpeciesCatalog {

    private(set) var all: [Species] = []
    private var byLabel: [String: Species] = [:]

    static let shared = SpeciesCatalog()

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "species_catalog", withExtension: "json") else {
            assertionFailure("species_catalog.json missing from bundle — run tools/build_catalog.py")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Species].self, from: data)
            all = decoded.sorted { $0.dexNumber < $1.dexNumber }
            byLabel = Dictionary(uniqueKeysWithValues: decoded.map { ($0.labelKey, $0) })
        } catch {
            assertionFailure("species_catalog.json failed to decode: \(error)")
        }
    }

    /// Resolve a recognizer label to a dex entry. Returns nil for labels that are
    /// not catchable (hypernyms, non-creatures).
    func species(forLabel label: String) -> Species? {
        byLabel[label] ?? Self.debugSubjects[label]
    }

    var totalCount: Int { all.count }

    func species(ofType type: TaxonType) -> [Species] {
        all.filter { $0.taxonType == type }
    }

    // MARK: - Debug test subjects

    /// Always-available recognition targets, deliberately kept out of the
    /// shipped 137-species catalog.
    ///
    /// A real animal is not always around when you want to check that the
    /// on-device recognizer is actually working. A person is. `species(forLabel:)`
    /// resolves these the same way it resolves a real species — the whole
    /// detect → lock → shutter → catch sequence fires normally — but they are
    /// excluded from `all`/`totalCount` and never appear in the Entries grid, so
    /// they cannot inflate dex completion or clutter the real collection.
    ///
    /// That exclusion has a second effect worth being explicit about: because
    /// `EntryDetailView`'s share control is only reachable by tapping a grid
    /// tile, a debug catch can never be shared to the community backend. Sharing
    /// a photo of a person — possibly a bystander who never consented — to a
    /// public map is a materially different privacy question than sharing a
    /// photo of a squirrel, so this is not sharable by construction rather than
    /// by a flag someone has to remember to check.
    static let debugSubjects: [String: Species] = {
        let human = Species(
            labelKey: "adult",
            dexNumber: 0,
            commonName: "Human (Test Target)",
            scientificName: "Homo sapiens",
            taxonType: .other,
            // A real, large observation count rather than a hand-picked rarity:
            // whatever formula Rarity.tier(forObservationCount:) ends up being,
            // a person is always going to land at the "extremely common" end,
            // so this needs no special-casing as that function changes.
            observationsCount: 8_000_000_000,
            dexDescription: "Not a real dex entry. Point the camera at yourself (or anyone nearby) to confirm the on-device recognizer is actually running — a person is available anywhere, unlike a snow leopard.",
            wikipediaURL: nil,
            photoAttribution: nil
        )
        return [human.labelKey: human]
    }()
}
