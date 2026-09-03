import Foundation

/// One dex entry. Everything except `labelKey` and `dexNumber` is ingested from
/// the iNaturalist API by `tools/build_catalog.py`, so descriptions and taxonomy
/// stay authoritative rather than hand-written.
struct Species: Codable, Identifiable, Hashable, Sendable {
    /// Recognizer output key. For the Vision baseline this is a `VNClassifyImageRequest`
    /// identifier (e.g. `"squirrel"`); for the Core ML model it will be a class label.
    /// It is the join key between the recognizer and this catalog.
    let labelKey: String

    /// Stable dex position, `No. 001` upward. Assigned at catalog build time and
    /// never reordered — a dex whose numbers shift is not a dex.
    let dexNumber: Int

    let commonName: String
    let scientificName: String
    let taxonType: TaxonType

    /// Global iNaturalist observation count. The sole input to rarity.
    let observationsCount: Int

    /// Short flavor description, from the Wikipedia REST summary endpoint.
    let dexDescription: String

    let wikipediaURL: String?

    /// iNat photos carry varying CC licenses, so we record attribution rather
    /// than bundling images with unclear terms.
    let photoAttribution: String?

    var id: String { labelKey }

    var rarity: Rarity { Rarity.tier(forObservationCount: observationsCount) }

    var formattedNumber: String { Theme.entryNumber(dexNumber) }
}
