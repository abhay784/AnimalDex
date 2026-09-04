import CoreLocation
import Foundation

/// Controls how precisely a shared catch's location is published.
///
/// This is the only place coordinates are transformed before leaving the device.
/// Everything that shares a catch goes through `obscuredCoordinate(for:rarity:)`,
/// so the policy lives in exactly one function rather than being re-decided at
/// each call site.
enum LocationPrivacy {

    /// How the user wants their shared pins handled. Persisted in UserDefaults
    /// and surfaced on the Trainer tab.
    enum Mode: String, CaseIterable, Identifiable {
        /// Publish the exact GPS fix.
        case exact
        /// Snap to a coarse grid.
        case fuzzed
        /// Share the catch but no location at all.
        case withheld

        var id: String { rawValue }

        var title: String {
            switch self {
            case .exact:    return "EXACT"
            case .fuzzed:   return "APPROXIMATE"
            case .withheld: return "NO LOCATION"
            }
        }

        var explanation: String {
            switch self {
            case .exact:
                return "Pins show precisely where you stood."
            case .fuzzed:
                return "Pins are nudged onto a coarse grid before sharing."
            case .withheld:
                return "Catches are shared without any location."
            }
        }
    }

    static var mode: Mode {
        get {
            UserDefaults.standard.string(forKey: "animaldex.locationPrivacy")
                .flatMap(Mode.init(rawValue:)) ?? .fuzzed
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "animaldex.locationPrivacy") }
    }

    /// Transform a catch's coordinate into what should actually be published.
    ///
    /// - Parameters:
    ///   - coordinate: The recorded fix, or nil if the catch has none.
    ///   - rarity: The species' tier. Available because rarity is exactly the
    ///     signal that makes a location sensitive.
    /// - Returns: The coordinate to send, or nil to publish no location.
    ///
    /// ## Why this is yours to decide
    ///
    /// This is a real safety decision, not a formatting one.
    ///
    /// Exact GPS on wildlife photos routinely reveals **where someone lives** —
    /// most people's first catches are in their own garden, and a cluster of
    /// pins around one address is not subtle. Separately, precise locations of
    /// rare species are a known collection and poaching vector; iNaturalist
    /// automatically obscures threatened taxa to roughly a 25km box for exactly
    /// this reason, and they arrived at that policy after real incidents.
    ///
    /// ## Approaches worth weighing
    ///
    /// - **Uniform grid snap.** Round to N decimal places. Simple and
    ///   predictable, but a grid is *reversible in aggregate*: many catches from
    ///   one person all snapping to the same cell still identifies the cell.
    /// - **Random offset per catch.** Displace by a random bearing and distance.
    ///   Harder to aggregate, but two catches at the same spot land in different
    ///   places, which looks wrong on a map.
    /// - **Random offset per *user*, fixed.** A stable per-user displacement
    ///   keeps relative geometry intact while moving the whole cluster.
    /// - **Rarity-dependent.** Fuzz only rare tiers, on the theory that a pigeon
    ///   needs no protection. Note the flaw: the *common* catches are the ones
    ///   near home.
    ///
    /// ## The trade-off
    ///
    /// Precision is what makes the map worth opening — "someone saw an owl in
    /// this park" is useful, "somewhere in this county" is not. But the cost of
    /// getting it wrong is borne by your users and by the animals, not by you.
    /// A useful reference point: 3 decimal places is about 110m, 2 is about
    /// 1.1km, and 1 is about 11km.
    ///
    /// Roughly 8 lines. Replace the placeholder below.
    static func obscuredCoordinate(
        for coordinate: CLLocationCoordinate2D?,
        rarity: Rarity
    ) -> CLLocationCoordinate2D? {
        guard let coordinate else { return nil }

        switch mode {
        case .withheld:
            return nil
        case .exact:
            return coordinate
        case .fuzzed:
            // TODO: (yours) Decide how a shared pin is obscured. See above.
            //
            // Placeholder: a naive 2-decimal grid snap (~1.1km cells). It is
            // deliberately the simplest thing that could work, and it has the
            // aggregation weakness described above — every catch you make at
            // home lands on the same cell centre, which over time points
            // straight back at your address.
            return CLLocationCoordinate2D(
                latitude: (coordinate.latitude * 100).rounded() / 100,
                longitude: (coordinate.longitude * 100).rounded() / 100
            )
        }
    }
}
