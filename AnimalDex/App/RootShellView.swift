import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case scanner, entries, map, profile

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scanner: return "SCAN"
        case .entries: return "DEX"
        case .map:     return "MAP"
        case .profile: return "TRAINER"
        }
    }

    var symbol: String {
        switch self {
        case .scanner: return "camera.viewfinder"
        case .entries: return "square.grid.3x3.fill"
        case .map:     return "map.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .scanner: return "FIELD SCANNER"
        case .entries: return "DEX ENTRIES"
        case .map:     return "SIGHTINGS MAP"
        case .profile: return "TRAINER CARD"
        }
    }
}

struct RootShellView: View {
    /// Scanner is the landing tab: the brief is that the app opens to a camera.
    @State private var tab: RootTab = .scanner
    @State private var scanner = ScannerViewModel()

    var body: some View {
        DexChromeView(title: tab.title, isActive: isLocked, tab: $tab) {
            switch tab {
            case .scanner: ScannerView(model: scanner)
            case .entries: EntriesGridView()
            case .map:     CatchMapView()
            case .profile: ProfileView()
            }
        }
    }

    private var isLocked: Bool {
        if case .locked = scanner.gateState { return true }
        return false
    }
}
