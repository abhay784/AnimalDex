import XCTest
@testable import AnimalDex

/// Regression coverage for the breed-alias table.
///
/// The alias mechanism exists because Vision is sometimes more specific than
/// the catalog — 39 dog-breed identifiers where the catalog only has "dog" —
/// and it fails silently: a typo'd alias target just means that breed's
/// photos never catch, with no crash and no obvious symptom short of someone
/// noticing their dog won't scan. These tests catch that at build time instead.
final class RecognitionTests: XCTestCase {

    private var catalog: SpeciesCatalog!

    override func setUp() {
        super.setUp()
        catalog = SpeciesCatalog()
    }

    func testEveryAliasTargetIsActuallyCatchable() {
        for (breed, canonical) in CreatureLabels.breedAliases {
            XCTAssertNotNil(
                catalog.species(forLabel: canonical),
                "\(breed) aliases to '\(canonical)', which does not resolve to any species"
            )
        }
    }

    /// The bug this whole mechanism fixes: a real dog breed label must resolve
    /// through the alias to the one canonical dog entry.
    func testCorgiResolvesToDog() {
        XCTAssertEqual(CreatureLabels.breedAliases["corgi"], "dog")
        XCTAssertEqual(catalog.species(forLabel: "dog")?.commonName, "Domestic Dog")
    }

    func testAdultCatResolvesToCat() {
        XCTAssertEqual(CreatureLabels.breedAliases["adult_cat"], "cat")
        XCTAssertEqual(catalog.species(forLabel: "cat")?.commonName, "Domestic Cat")
    }

    /// An alias key should never coincide with an existing catalog label — that
    /// would mean silently redirecting a real, independently-mapped species
    /// onto a different one.
    func testNoAliasKeyShadowsARealCatalogEntry() {
        let realLabels = Set(catalog.all.map(\.labelKey))
        let shadowed = CreatureLabels.breedAliases.keys.filter { realLabels.contains($0) }
        XCTAssertTrue(shadowed.isEmpty, "alias keys already have their own catalog entry: \(shadowed)")
    }
}
