import SwiftUI

/// Pokémon-style collectability tiers.
///
/// Rarity is *derived*, not authored: every species in the catalog carries its
/// global iNaturalist observation count, and that number maps onto a tier.
/// Fewer sightings worldwide → rarer catch.
enum Rarity: String, Codable, CaseIterable, Comparable, Sendable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    private var order: Int {
        switch self {
        case .common: return 0
        case .uncommon: return 1
        case .rare: return 2
        case .epic: return 3
        case .legendary: return 4
        }
    }

    static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.order < rhs.order }

    var displayName: String { rawValue.uppercased() }

    /// Frame and glow color for cards, pins, and the detection banner.
    var color: Color {
        switch self {
        case .common:    return Color(hex: 0x9E9E9E)
        case .uncommon:  return Color(hex: 0x4CBB4C)
        case .rare:      return Color(hex: 0x2B7FD4)
        case .epic:      return Color(hex: 0x9B4FD1)
        case .legendary: return Color(hex: 0xF2C438)
        }
    }

    /// Escalating card treatment: plain → colored → metallic → gradient → foil.
    var usesGradientFrame: Bool { self >= .epic }
    var usesHolographicFoil: Bool { self == .legendary }

    /// How many shake beats the catch sequence plays before resolving.
    /// Rarer creatures hold the tension longer.
    var shakeCount: Int {
        switch self {
        case .common:    return 1
        case .uncommon:  return 2
        case .rare:      return 3
        case .epic:      return 3
        case .legendary: return 4
        }
    }

    // MARK: - Derivation

    /// Maps a species' global iNaturalist observation count onto a rarity tier.
    ///
    /// - Parameter count: Global observation count from the iNaturalist API
    ///   (`observations_count` on a taxon).
    /// - Returns: The tier this species should occupy in the dex.
    ///
    /// ## Why this is yours to decide
    ///
    /// This single function sets how the entire game feels. It is the difference
    /// between "everything I find is Legendary, so nothing is" and "I have played
    /// for an hour and everything is still Common."
    ///
    /// ## Real anchors, pulled from the live API
    ///
    /// | Species                  | Observations |
    /// |--------------------------|--------------|
    /// | House Sparrow            |      560,649 |
    /// | Monarch butterfly        |      531,692 |
    /// | Eastern Gray Squirrel    |      401,630 |
    /// | Bald Eagle               |      234,888 |
    /// | Luna Moth                |       69,772 |
    /// | Mexican Armadillo        |       37,910 |
    /// | Blue-spotted Salamander  |       15,137 |
    /// | Snow Leopard             |        1,191 |
    ///
    /// Counts in the full catalog span roughly 10^2 to 10^6 — about four orders
    /// of magnitude. That is the key constraint: **linear cutoffs will not work.**
    /// If you split 0…560,000 into five equal bands, everything except the house
    /// sparrow lands in the bottom band and the whole dex reads as Common.
    ///
    /// ## Approaches worth weighing
    ///
    /// - **Log-scale thresholds.** Take `log10(count)` and cut on that — e.g. a
    ///   species with 10^5+ sightings is Common, 10^4 is Uncommon, and so on.
    ///   Smooth and principled, but you still choose where the lines land.
    /// - **Hand-tuned breakpoints.** Pick literal counts that put species you
    ///   personally care about in the tiers you want them in. Less elegant,
    ///   more controllable.
    /// - **Curve + squash.** Normalize log-count into 0…1, then apply an easing
    ///   curve so the top tiers stay genuinely scarce.
    ///
    /// ## The trade-off
    ///
    /// Generous tiers make the first session feel rewarding but devalue a real
    /// find — if a pigeon is Rare, a Snow Leopard cannot feel special. Harsh
    /// tiers make Legendary mean something but risk an opening hour where every
    /// catch is gray. There is no correct answer here, which is exactly why it
    /// should be your call rather than mine.
    ///
    /// Roughly 8 lines. Replace the placeholder below.
    static func tier(forObservationCount count: Int) -> Rarity {
        // TODO: (yours) Map `count` onto a tier. See the discussion above.
        //
        // Placeholder so the app compiles and runs end-to-end in the meantime.
        // It is deliberately naive — every species below 100k reads as Rare or
        // better, which is exactly the "everything is Legendary" failure mode
        // described above. Swapping this out is the intended first change.
        switch count {
        case 250_000...:      return .common
        case 100_000..<250_000: return .uncommon
        case 25_000..<100_000:  return .rare
        case 5_000..<25_000:    return .epic
        default:                return .legendary
        }
    }
}
