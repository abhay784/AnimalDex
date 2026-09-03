import SwiftUI

/// The "type" system, borrowed wholesale from iNaturalist's `iconic_taxon_name`.
/// Using their taxonomy instead of inventing one means every species we ingest
/// arrives pre-typed and stays scientifically correct for free.
enum TaxonType: String, Codable, CaseIterable, Sendable {
    case aves            = "Aves"
    case insecta         = "Insecta"
    case mammalia        = "Mammalia"
    case arachnida       = "Arachnida"
    case reptilia        = "Reptilia"
    case amphibia        = "Amphibia"
    case actinopterygii  = "Actinopterygii"
    case mollusca        = "Mollusca"
    case other           = "Animalia"

    /// Short label for the badge pill.
    var displayName: String {
        switch self {
        case .aves:           return "BIRD"
        case .insecta:        return "INSECT"
        case .mammalia:       return "MAMMAL"
        case .arachnida:      return "ARACHNID"
        case .reptilia:       return "REPTILE"
        case .amphibia:       return "AMPHIBIAN"
        case .actinopterygii: return "FISH"
        case .mollusca:       return "MOLLUSC"
        case .other:          return "CREATURE"
        }
    }

    var color: Color {
        switch self {
        case .aves:           return Color(hex: 0x5AAEE0)
        case .insecta:        return Color(hex: 0x8FBF3F)
        case .mammalia:       return Color(hex: 0xC97B3C)
        case .arachnida:      return Color(hex: 0x7B5EA8)
        case .reptilia:       return Color(hex: 0x3FA86B)
        case .amphibia:       return Color(hex: 0x46B8A0)
        case .actinopterygii: return Color(hex: 0x3D74C4)
        case .mollusca:       return Color(hex: 0xD06BA0)
        case .other:          return Color(hex: 0x8A8A8A)
        }
    }

    var systemImage: String {
        switch self {
        case .aves:           return "bird.fill"
        case .insecta:        return "ant.fill"
        case .mammalia:       return "hare.fill"
        case .arachnida:      return "ladybug.fill"
        case .reptilia:       return "lizard.fill"
        case .amphibia:       return "drop.fill"
        case .actinopterygii: return "fish.fill"
        case .mollusca:       return "shell.fill"
        case .other:          return "pawprint.fill"
        }
    }
}

/// The pill badge itself.
struct TypeBadge: View {
    let type: TaxonType
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: type.systemImage)
                .font(.system(size: compact ? 8 : 10, weight: .black))
            Text(type.displayName)
                .font(Theme.display(compact ? 9 : 11))
                .tracking(0.6)
        }
        .outlinedText()
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 3 : 5)
        .background(
            Capsule().fill(type.color)
        )
        .overlay(
            Capsule().strokeBorder(Theme.outline, lineWidth: 2)
        )
    }
}
