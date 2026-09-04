import SwiftUI
import SwiftData

@main
struct AnimalDexApp: App {

    private let container: ModelContainer = {
        do {
            return try ModelContainer(for: CatchRecord.self)
        } catch {
            // A dex with no store is not a degraded app, it's a different app.
            fatalError("Could not open the local Dex store: \(error)")
        }
    }()

    @State private var catalog = SpeciesCatalog.shared
    @State private var session: SessionStore
    @State private var sync: SyncEngine
    @State private var hasBooted = false

    init() {
        // SyncEngine needs the session, so both are constructed here rather than
        // as default property initialisers.
        let session = SessionStore()
        _session = State(initialValue: session)
        _sync = State(initialValue: SyncEngine(session: session))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasBooted {
                    RootShellView()
                        .transition(.opacity)
                } else {
                    BootSequenceView { hasBooted = true }
                }
            }
            .environment(catalog)
            .environment(session)
            .environment(sync)
            .preferredColorScheme(.light)
            .task {
                SoundBank.shared.preload()
                Haptics.prepare()
            }
        }
        .modelContainer(container)
    }
}
