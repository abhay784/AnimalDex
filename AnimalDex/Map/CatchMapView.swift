import SwiftUI
import SwiftData
import MapKit

/// Sightings map.
///
/// MapKit for v1, reached only through this file so that swapping to the Google
/// Maps SDK later stays a contained change rather than a scavenger hunt.
/// Community pins from the backend will render alongside these using the same
/// annotation view.
struct CatchMapView: View {
    @Environment(SpeciesCatalog.self) private var catalog
    @Query(sort: \CatchRecord.capturedAt, order: .reverse) private var catches: [CatchRecord]

    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: CatchRecord?

    private var located: [CatchRecord] { catches.filter { $0.coordinate != nil } }

    var body: some View {
        ZStack {
            Map(position: $camera) {
                ForEach(located) { record in
                    if let coordinate = record.coordinate {
                        Annotation(
                            catalog.species(forLabel: record.speciesKey)?.commonName ?? "",
                            coordinate: coordinate
                        ) {
                            CatchAnnotationView(
                                record: record,
                                species: catalog.species(forLabel: record.speciesKey)
                            )
                            .onTapGesture {
                                SoundBank.shared.play(.select)
                                selected = record
                            }
                        }
                    }
                }
                UserAnnotation()
            }
            .mapControlVisibility(.hidden)

            if located.isEmpty { emptyState }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    recenterButton
                }
            }
            .padding(16)
        }
        .sheet(item: $selected) { record in
            if let species = catalog.species(forLabel: record.speciesKey) {
                EntryDetailView(species: species, catches: [record])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 34, weight: .black))
            Text("NO SIGHTINGS PINNED YET")
                .font(Theme.display(13))
                .tracking(1.2)
            Text("Catches record where you found them.\nAllow location access to see them here.")
                .font(Theme.screenText(10))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.phosphor)
        .padding(22)
        .background(Theme.lcd.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.outline, lineWidth: 3))
        .padding(30)
    }

    private var recenterButton: some View {
        Button {
            SoundBank.shared.play(.select)
            withAnimation { camera = .userLocation(fallback: .automatic) }
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(Theme.panel)
                .padding(13)
                .background(Circle().fill(Theme.shell))
                .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 3))
                .shadow(color: .black.opacity(0.4), radius: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

/// A catch pin: the photo you took, ringed in its rarity color.
struct CatchAnnotationView: View {
    let record: CatchRecord
    let species: Species?

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.panel)
                .frame(width: 46, height: 46)

            if let image = PhotoStore.shared.load(record.photoFilename) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else if let species {
                Image(systemName: species.taxonType.systemImage)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(Theme.outline)
            }

            Circle()
                .strokeBorder(species?.rarity.color ?? Theme.outline, lineWidth: 4)
                .frame(width: 46, height: 46)
        }
        .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 1.5).frame(width: 48, height: 48))
        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
    }
}
