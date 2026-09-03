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
        "raptor", "hound", "poultry", "seafood",
    ]

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
