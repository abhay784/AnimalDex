import SwiftUI
import SwiftData

struct EntryDetailView: View {
    let species: Species
    let catches: [CatchRecord]

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DexCardView(
                        species: species,
                        image: catches.first.flatMap { PhotoStore.shared.load($0.photoFilename) }
                    )

                    shareControl

                    if catches.count > 1 { history }

                    if let attribution = species.photoAttribution {
                        Text(attribution)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.outline.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(16)
            }
            .background(Theme.phosphorDim)
            .navigationTitle(species.commonName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Sharing is per catch and opt-in. Nothing leaves the device by default,
    /// and the copy says exactly what will be published — including that the
    /// location is transformed by the user's own precision setting first.
    @ViewBuilder
    private var shareControl: some View {
        if let record = catches.first {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: record.isSharedToCommunity ? "globe.americas.fill" : "lock.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(record.isSharedToCommunity ? Theme.ledGreen : Theme.outline.opacity(0.5))
                    Text(record.isSharedToCommunity ? "SHARED WITH COMMUNITY" : "PRIVATE TO THIS DEVICE")
                        .accessibilityIdentifier("entry.shareStatus")
                        .font(Theme.display(11))
                        .tracking(1)
                        .foregroundStyle(Theme.outline)
                    Spacer()
                }

                if !record.isSharedToCommunity {
                    Text(shareExplanation(for: record))
                        .font(Theme.screenText(9))
                        .foregroundStyle(Theme.outline.opacity(0.65))

                    Button {
                        SoundBank.shared.play(.select)
                        Task { await sync.share(record, species: species, context: context) }
                    } label: {
                        HStack(spacing: 7) {
                            if sync.isSyncing { ProgressView().tint(.white).scaleEffect(0.8) }
                            Text(session.isSignedIn ? "SHARE THIS SIGHTING" : "SIGN IN TO SHARE")
                                .font(Theme.display(12))
                                .tracking(1.1)
                                .outlinedText()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 10).fill(session.isSignedIn ? Theme.lens : Theme.outline.opacity(0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.outline, lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("entry.share")
                    .disabled(!session.isSignedIn || sync.isSyncing)
                }

                if let message = sync.errorMessage {
                    Text(message.uppercased())
                        .font(Theme.screenText(9))
                        .foregroundStyle(Theme.phosphor)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .screenSurface(Theme.lcd, radius: 6)
                }
            }
            .padding(14)
            .bevelPanel()
        }
    }

    private func shareExplanation(for record: CatchRecord) -> String {
        guard record.coordinate != nil else {
            return "Your photo and the species will be published. This catch has no location recorded."
        }
        switch LocationPrivacy.mode {
        case .exact:
            return "Your photo, the species, and the exact spot you found it will be published."
        case .fuzzed:
            return "Your photo and the species will be published. The location is rounded before it leaves your device."
        case .withheld:
            return "Your photo and the species will be published. No location will be shared."
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTURE LOG — ×\(catches.count)")
                .font(Theme.display(11))
                .tracking(1.2)
                .foregroundStyle(Theme.outline.opacity(0.7))

            ForEach(catches) { record in
                HStack(spacing: 10) {
                    if let image = PhotoStore.shared.load(record.photoFilename) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.capturedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.screenText(11))
                        Text("\(Int(record.confidence * 100))% MATCH" + (record.coordinate == nil ? " · NO LOCATION" : ""))
                            .font(Theme.display(8))
                            .foregroundStyle(Theme.outline.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(8)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.outline, lineWidth: 2))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
