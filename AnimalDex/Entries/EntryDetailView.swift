import SwiftUI
import SwiftData

struct EntryDetailView: View {
    let species: Species
    let catches: [CatchRecord]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DexCardView(
                        species: species,
                        image: catches.first.flatMap { PhotoStore.shared.load($0.photoFilename) }
                    )

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
