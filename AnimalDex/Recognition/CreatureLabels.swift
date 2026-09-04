import Foundation

/// Label sets used to interpret `VNClassifyImageRequest` output.
///
/// Note what is *not* here: a list of catchable creatures. The bundled species
/// catalog is that list — `SpeciesCatalog.species(forLabel:)` returning non-nil
/// is the definition of "catchable". Keeping a second hand-maintained allowlist
/// would let the two drift apart silently, which is the most likely way this
/// layer breaks.
enum CreatureLabels {

    /// Umbrella labels Vision emits *alongside* a specific one — `bird` fires
    /// with `sparrow`, `mammal` with `fox`.
    ///
    /// These are never dex entries. If one fires but nothing specific does, the
    /// app knows a creature is present but can't name it, which becomes the
    /// "get closer" mechanic rather than a junk entry.
    static let hypernyms: Set<String> = [
        "animal", "mammal", "bird", "fish", "insect", "reptile", "arachnid",
        "rodent", "canine", "feline", "marsupial", "ungulates", "arthropods",
        "cetacean", "gastropod", "cephalopod", "mollusk", "shellfish",
        "raptor", "poultry", "seafood",
    ]

    /// Vision labels that are more specific than anything in the catalog,
    /// mapped onto the one dex entry they should register as.
    ///
    /// Discovered from a real bug report: scanning a dog produced nothing. The
    /// catalog only knows the generic `"dog"` (→ Domestic Dog), but Vision has a
    /// breed-level taxonomy — 39 distinct identifiers — and for a photo with a
    /// recognisable breed it reports the breed at high confidence and the
    /// generic `"dog"` barely at all, so the generic label alone never crossed
    /// the gate's threshold. This is not a dog-only shape: any category where
    /// Vision's granularity is finer than the catalog's will fail the same way.
    ///
    /// Applied before the catchable/hypernym check in
    /// `VisionBuiltinRecognizer.classify(_:)` — the *raw* breed label is still
    /// what appears in the diagnostics overlay, so `corgi 0.87` stays legible;
    /// only the resulting `RecognitionCandidate` is canonicalised, which is what
    /// lets `SpeciesCatalog.species(forLabel:)` resolve it.
    static let breedAliases: [String: String] = {
        let dogBreeds = [
            "australian_shepherd", "basenji", "basset", "beagle",
            "bernese_mountain", "bichon", "bulldog", "chihuahua", "collie",
            "corgi", "dachshund", "dalmatian", "doberman", "german_shepherd",
            "greyhound", "hound", "husky", "irish_wolfhound",
            "jack_russell_terrier", "malamute", "malinois", "mastiff",
            "newfoundland", "pitbull", "pomeranian", "poodle", "pug",
            "retriever", "ridgeback", "rottweiler", "saint_bernard",
            "schnauzer", "setter", "sheepdog", "spaniel", "terrier", "vizsla",
            "weimaraner",
        ]
        var map = Dictionary(uniqueKeysWithValues: dogBreeds.map { ($0, "dog") })
        // Vision's cat equivalent of "adult" — a grown-cat age marker, not a
        // breed, but the same "more specific than the catalog" shape.
        map["adult_cat"] = "cat"
        return map
    }()

    /// Context labels that mean the "creature" on screen is lunch.
    ///
    /// `salmon`, `crab`, `lobster`, and `oyster` are all real animals and all
    /// overwhelmingly photographed on plates. Vision is multi-label, so when any
    /// of these co-occur above threshold we reject the catch rather than
    /// congratulate someone on discovering sushi.
    static let foodContext: Set<String> = [
        "food", "seafood", "shellfish_prepared", "meat", "restaurant",
        "plate", "cookware", "dessert", "sushi", "tableware", "cutting_board",
        "kitchen", "salad", "soup", "steak", "sandwich", "pizza", "grill",
    ]

    /// Confidence a food-context label needs before it vetoes a catch.
    /// Deliberately low — a false veto costs one retry, a false catch pollutes
    /// the dex permanently.
    static let foodVetoThreshold: Float = 0.25

    /// Labels for captive/enclosure contexts. Not a veto — catching something at
    /// a zoo or aquarium is legitimate — but flagged on the entry for honesty.
    static let captivityContext: Set<String> = [
        "zoo", "aquarium", "cage", "terrarium", "fishtank", "fishbowl",
    ]
}
