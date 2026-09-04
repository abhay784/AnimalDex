import CoreLocation
import XCTest
@testable import AnimalDex

final class CatalogTests: XCTestCase {

    private var catalog: SpeciesCatalog!

    override func setUp() {
        super.setUp()
        catalog = SpeciesCatalog()
    }

    func testCatalogLoads() {
        XCTAssertEqual(catalog.totalCount, 137, "dex size changed — was the catalog rebuilt?")
    }

    /// The human test subject must resolve (so the recognizer can catch it) but
    /// must never count toward the real dex — that is the whole point of it
    /// being a debug subject rather than a 138th species.
    func testDebugSubjectResolvesButIsExcludedFromTheRealDex() {
        let human = catalog.species(forLabel: "adult")
        XCTAssertNotNil(human, "debug subject 'adult' should resolve")
        XCTAssertFalse(
            catalog.all.contains { $0.labelKey == "adult" },
            "debug subjects must not appear in the shipped catalog"
        )
        XCTAssertEqual(catalog.totalCount, 137, "resolving a debug subject must not change dex size")
    }

    /// Dex numbers are identity. If they shift, every saved catch points at a
    /// different creature than it did before.
    func testDexNumbersAreContiguousAndStable() {
        let numbers = catalog.all.map(\.dexNumber)
        XCTAssertEqual(numbers, Array(1...catalog.totalCount))
    }

    func testNoDuplicateTaxa() {
        let scientific = catalog.all.map(\.scientificName)
        XCTAssertEqual(
            Set(scientific).count, scientific.count,
            "two labels resolved to the same species — that is two dex slots for one animal"
        )
    }

    func testEveryEntryHasFieldNotes() {
        let empty = catalog.all.filter { $0.dexDescription.isEmpty }
        XCTAssertTrue(empty.isEmpty, "entries with no description: \(empty.map(\.labelKey))")
    }

    /// The recognizer resolves a label by asking the catalog. Any label the
    /// recognizer can emit but the catalog cannot resolve is a dead dex slot.
    func testHypernymsAreNotCatchable() {
        for hypernym in CreatureLabels.hypernyms {
            XCTAssertNil(
                catalog.species(forLabel: hypernym),
                "\(hypernym) is an umbrella label and must not be a dex entry"
            )
        }
    }

    func testFoodContextLabelsAreNotCatchable() {
        for label in CreatureLabels.foodContext {
            XCTAssertNil(catalog.species(forLabel: label))
        }
    }

    /// Rarity is derived, so every entry must produce one.
    func testEveryEntryHasARarity() {
        for species in catalog.all {
            XCTAssertGreaterThan(species.observationsCount, 0, "\(species.labelKey) has no sightings")
            _ = species.rarity
        }
    }
}

/// Contract tests for the location-privacy policy.
///
/// These deliberately assert the *contract* rather than any particular fuzzing
/// algorithm, so they keep passing when the `.fuzzed` implementation is replaced.
final class LocationPrivacyTests: XCTestCase {

    private let ucsd = CLLocationCoordinate2D(latitude: 32.8801, longitude: -117.2340)

    override func tearDown() {
        LocationPrivacy.mode = .fuzzed
        super.tearDown()
    }

    func testNoCoordinateStaysNoCoordinate() {
        for mode in LocationPrivacy.Mode.allCases {
            LocationPrivacy.mode = mode
            XCTAssertNil(LocationPrivacy.obscuredCoordinate(for: nil, rarity: .common))
        }
    }

    func testWithheldPublishesNothing() {
        LocationPrivacy.mode = .withheld
        XCTAssertNil(LocationPrivacy.obscuredCoordinate(for: ucsd, rarity: .legendary))
    }

    func testExactIsUnchanged() {
        LocationPrivacy.mode = .exact
        let result = LocationPrivacy.obscuredCoordinate(for: ucsd, rarity: .common)
        XCTAssertEqual(result?.latitude, ucsd.latitude)
        XCTAssertEqual(result?.longitude, ucsd.longitude)
    }

    /// Whatever policy is chosen, a fuzzed pin must stay in roughly the right
    /// place — useful to the map and not a different city.
    func testFuzzedStaysWithinASaneRadius() {
        LocationPrivacy.mode = .fuzzed
        guard let result = LocationPrivacy.obscuredCoordinate(for: ucsd, rarity: .rare) else {
            return XCTFail("fuzzed mode should still publish a coordinate")
        }
        let moved = CLLocation(latitude: result.latitude, longitude: result.longitude)
            .distance(from: CLLocation(latitude: ucsd.latitude, longitude: ucsd.longitude))
        XCTAssertLessThan(moved, 50_000, "fuzzing moved the pin more than 50km")
    }
}
