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
        byLabel[label]
    }

    var totalCount: Int { all.count }

    func species(ofType type: TaxonType) -> [Species] {
        all.filter { $0.taxonType == type }
    }
}
