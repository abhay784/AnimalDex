"""Vision label -> representative iNaturalist species.

Apple's built-in classifier is coarse: it emits `sparrow`, not `House Sparrow`.
Each coarse label is therefore mapped to one *representative* species, whose real
observation count drives that entry's rarity. This is an honest approximation and
is flagged as such in the UI; Track B's custom model replaces it with true
species-level identification.

Third element is the expected iNat iconic taxon. It is not decoration: without
it the API's fuzzy search returns "common dandelion" for `lion` and "Japanese
knotweed" for `donkey`, because it substring-matches across every kingdom.

Order here IS dex order. Entries are grouped by taxon so the dex reads like a
field guide: birds first, then insects, and so on. Never reorder an existing
entry — dex numbers are stable identity, and a dex whose numbers shift is not a dex.
"""

LABEL_MAP: list[tuple[str, str, str]] = [
    # --- Aves -------------------------------------------------------------
    ("sparrow", "House Sparrow", "Aves"),
    ("pigeon", "Rock Pigeon", "Aves"),
    ("dove", "Mourning Dove", "Aves"),
    ("gull", "Herring Gull", "Aves"),
    ("raven", "Common Raven", "Aves"),
    ("woodpecker", "Downy Woodpecker", "Aves"),
    ("hummingbird", "Ruby-throated Hummingbird", "Aves"),
    ("sandpiper", "Spotted Sandpiper", "Aves"),
    ("heron", "Great Blue Heron", "Aves"),
    ("stork", "White Stork", "Aves"),
    ("swan", "Mute Swan", "Aves"),
    ("pelican", "Brown Pelican", "Aves"),
    ("owl", "Great Horned Owl", "Aves"),
    ("eagle", "Bald Eagle", "Aves"),
    ("peregrine", "Peregrine Falcon", "Aves"),
    ("vulture", "Turkey Vulture", "Aves"),
    ("parakeet", "Budgerigar", "Aves"),
    ("parrot", "Scarlet Macaw", "Aves"),
    ("cockatoo", "Sulphur-crested Cockatoo", "Aves"),
    ("toucan", "Toco Toucan", "Aves"),
    ("peacock", "Indian Peafowl", "Aves"),
    ("flamingo", "American Flamingo", "Aves"),
    ("puffin", "Atlantic Puffin", "Aves"),
    ("penguin", "Emperor Penguin", "Aves"),
    ("ostrich", "Common Ostrich", "Aves"),

    # --- Insecta ----------------------------------------------------------
    ("butterfly", "Monarch", "Insecta"),
    ("moth", "North American Luna Moth", "Insecta"),
    ("caterpillar", "Isabella Tiger Moth", "Insecta"),
    ("bee", "Western Honey Bee", "Insecta"),
    ("ant", "Black Carpenter Ant", "Insecta"),
    ("dragonfly", "Common Green Darner", "Insecta"),
    ("ladybug", "Seven-spotted Lady Beetle", "Insecta"),
    ("scarab", "Japanese Beetle", "Insecta"),

    # --- Arachnida --------------------------------------------------------
    ("spider", "European Garden Spider", "Arachnida"),
    ("scorpion", "Arizona Bark Scorpion", "Arachnida"),

    # --- Myriapoda (typed as "other") ------------------------------------
    ("centipede", "House Centipede", "Animalia"),
    ("millipede", "American Giant Millipede", "Animalia"),

    # --- Mammalia ---------------------------------------------------------
    ("squirrel", "Eastern Gray Squirrel", "Mammalia"),
    ("prairie_dog", "Black-tailed Prairie Dog", "Mammalia"),
    ("chinchilla", "Long-tailed Chinchilla", "Mammalia"),
    ("hamster", "Golden Hamster", "Mammalia"),
    ("gerbil", "Mongolian Gerbil", "Mammalia"),
    ("rat", "Brown Rat", "Mammalia"),
    ("porcupine", "North American Porcupine", "Mammalia"),
    ("rabbit", "Eastern Cottontail", "Mammalia"),
    ("hedgehog", "Erinaceus europaeus", "Mammalia"),
    ("raccoon", "Common Raccoon", "Mammalia"),
    ("skunk", "Striped Skunk", "Mammalia"),
    ("otter", "North American River Otter", "Mammalia"),
    ("ferret", "Black-footed Ferret", "Mammalia"),
    ("fox", "Red Fox", "Mammalia"),
    ("coyote_wolf", "Coyote", "Mammalia"),
    ("bobcat", "Bobcat", "Mammalia"),
    ("lynx", "Canada Lynx", "Mammalia"),
    ("cougar", "Cougar", "Mammalia"),
    ("leopard", "Leopard", "Mammalia"),
    ("cheetah", "Cheetah", "Mammalia"),
    ("tiger", "Panthera tigris", "Mammalia"),
    ("lion", "Lion", "Mammalia"),
    ("hyena", "Spotted Hyena", "Mammalia"),
    ("bear", "American Black Bear", "Mammalia"),
    ("panda", "Giant Panda", "Mammalia"),
    ("deer", "White-tailed Deer", "Mammalia"),
    ("elk", "Cervus canadensis", "Mammalia"),  # NOT Alces alces - "elk" means moose in Europe
    ("moose", "Moose", "Mammalia"),
    ("bison", "American Bison", "Mammalia"),
    ("boar", "Wild Boar", "Mammalia"),
    ("giraffe", "Giraffe", "Mammalia"),
    ("zebra", "Plains Zebra", "Mammalia"),
    ("rhinoceros", "White Rhinoceros", "Mammalia"),
    ("hippopotamus", "Hippopotamus", "Mammalia"),
    ("elephant", "African Bush Elephant", "Mammalia"),
    ("camel", "Dromedary", "Mammalia"),
    ("llama", "Lama glama", "Mammalia"),
    ("kangaroo", "Eastern Grey Kangaroo", "Mammalia"),
    ("koala", "Koala", "Mammalia"),
    ("lemur", "Ring-tailed Lemur", "Mammalia"),
    ("seal", "Harbor Seal", "Mammalia"),
    ("sealion", "California Sea Lion", "Mammalia"),
    ("walrus", "Walrus", "Mammalia"),
    ("dolphin", "Common Bottlenose Dolphin", "Mammalia"),
    ("whale", "Humpback Whale", "Mammalia"),
    ("horse", "Equus caballus", "Mammalia"),
    ("donkey", "Donkey", "Mammalia"),
    ("cow", "Domestic Cattle", "Mammalia"),
    ("sheep", "Domestic Sheep", "Mammalia"),
    ("goat", "Domestic Goat", "Mammalia"),
    ("pig", "Sus scrofa domesticus", "Mammalia"),  # subspecies; Sus scrofa itself is the wild boar
    ("dog", "Domestic Dog", "Mammalia"),
    ("cat", "Domestic Cat", "Mammalia"),

    # --- Reptilia ---------------------------------------------------------
    ("lizard", "Eastern Fence Lizard", "Reptilia"),
    ("gecko", "Common House Gecko", "Reptilia"),
    ("chameleon", "Veiled Chameleon", "Reptilia"),
    ("iguana", "Green Iguana", "Reptilia"),
    ("monitor_lizard", "Komodo Dragon", "Reptilia"),
    ("snake", "Common Garter Snake", "Reptilia"),
    ("rattlesnake", "Western Diamond-backed Rattlesnake", "Reptilia"),
    ("python", "Burmese Python", "Reptilia"),
    ("turtle", "Painted Turtle", "Reptilia"),
    ("tortoise", "Desert Tortoise", "Reptilia"),
    ("alligator_crocodile", "American Alligator", "Reptilia"),

    # --- Amphibia ---------------------------------------------------------
    ("frog", "American Bullfrog", "Amphibia"),
    ("toad", "American Toad", "Amphibia"),

    # --- Actinopterygii ---------------------------------------------------
    ("goldfish", "Goldfish", "Actinopterygii"),
    ("koi", "Common Carp", "Actinopterygii"),
    ("guppy", "Guppy", "Actinopterygii"),
    ("angelfish", "Freshwater Angelfish", "Actinopterygii"),
    ("clownfish", "Orange Clownfish", "Actinopterygii"),
    ("lionfish", "Red Lionfish", "Actinopterygii"),
    ("puffer_fish", "Northern Puffer", "Actinopterygii"),
    ("seahorse", "Lined Seahorse", "Actinopterygii"),
    ("sunfish", "Bluegill", "Actinopterygii"),
    ("trout", "Rainbow Trout", "Actinopterygii"),
    ("salmon", "Sockeye Salmon", "Actinopterygii"),
    ("tuna", "Yellowfin Tuna", "Actinopterygii"),
    ("mackerel", "Atlantic Mackerel", "Actinopterygii"),
    ("anchovy", "European Anchovy", "Actinopterygii"),
    ("sardine", "European Pilchard", "Actinopterygii"),
    ("snapper", "Northern Red Snapper", "Actinopterygii"),
    ("seabass", "European Seabass", "Actinopterygii"),
    ("barracuda", "Great Barracuda", "Actinopterygii"),
    ("swordfish", "Swordfish", "Actinopterygii"),
    ("stingray", "Southern Stingray", "Actinopterygii"),
    ("shark", "Great White Shark", "Actinopterygii"),

    # --- Mollusca ---------------------------------------------------------
    ("snail", "Brown Garden Snail", "Mollusca"),
    ("clam", "Hard Clam", "Mollusca"),
    ("mussel", "Blue Mussel", "Mollusca"),
    ("oyster", "Eastern Oyster", "Mollusca"),
    ("scallop", "Atlantic Bay Scallop", "Mollusca"),
    ("conch", "Queen Conch", "Mollusca"),

    # --- Other invertebrates ---------------------------------------------
    ("crab", "Atlantic Blue Crab", "Animalia"),
    ("lobster", "American Lobster", "Animalia"),
    ("jellyfish", "Moon Jelly", "Animalia"),
    ("starfish", "Ochre Sea Star", "Animalia"),
    ("urchin", "Purple Sea Urchin", "Animalia"),
    ("barnacle", "Semibalanus balanoides", "Animalia"),
    ("worm", "Common Earthworm", "Animalia"),
]