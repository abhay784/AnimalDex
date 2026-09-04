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
    @Environment(SessionStore.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Query(sort: \CatchRecord.capturedAt, order: .reverse) private var catches: [CatchRecord]

    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: CatchRecord?
    @State private var showingCommunity = true
    @State private var lastCentre: CLLocationCoordinate2D?

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
                if showingCommunity {
                    ForEach(communityPins, id: \.id) { pin in
                        if let lat = pin.lat, let lng = pin.lng {
                            Annotation(
                                pin.handle,
                                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)
                            ) {
                                CommunityAnnotationView(
                                    species: catalog.species(forLabel: pin.speciesKey),
                                    handle: pin.handle
                                )
                            }
                        }
                    }
                }

                UserAnnotation()
            }
            .mapControlVisibility(.hidden)
            .onMapCameraChange(frequency: .onEnd) { context in
                let centre = context.region.center
                // Only refetch when the map has moved meaningfully. Firing on
                // every settle would hammer the endpoint during ordinary panning,
                // and the server-side cache buckets to ~110m anyway.
                if let last = lastCentre, distance(last, centre) < 2_000 { return }
                lastCentre = centre
                Task { await sync.refreshCommunity(around: centre) }
            }

            if located.isEmpty && communityPins.isEmpty { emptyState }

            VStack {
                HStack {
                    communityToggle
                    Spacer()
                }
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

    /// Community pins, minus anything already shown as one of your own — a
    /// catch you shared would otherwise render twice, once from SwiftData and
    /// once from the server.
    private var communityPins: [CatchDTO] {
        let mine = Set(catches.compactMap(\.remoteID))
        return sync.communityCatches.filter { !mine.contains($0.id) }
    }

    private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    @ViewBuilder
    private var communityToggle: some View {
        if session.isSignedIn {
            Button {
                SoundBank.shared.play(.select)
                showingCommunity.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showingCommunity ? "globe.americas.fill" : "person.fill")
                        .font(.system(size: 12, weight: .black))
                    Text(showingCommunity ? "COMMUNITY" : "MINE ONLY")
                        .font(Theme.display(10))
                        .tracking(0.8)
                }
                .outlinedText()
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Capsule().fill(showingCommunity ? Theme.lens : Theme.outline.opacity(0.75)))
                .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 2.5))
            }
            .buttonStyle(.plain)
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


/// A community sighting. Deliberately distinguishable from your own pins — a
/// square badge with the trainer's handle rather than a round photo — so the map
/// never implies you caught something you didn't.
struct CommunityAnnotationView: View {
    let species: Species?
    let handle: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.panel)
                    .frame(width: 34, height: 34)
                Image(systemName: species?.taxonType.systemImage ?? "pawprint.fill")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(species?.taxonType.color ?? Theme.outline)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(species?.rarity.color ?? Theme.outline, lineWidth: 3)
            )

            Text("@\(handle)")
                .font(Theme.display(8))
                .outlinedText()
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.outline.opacity(0.8)))
        }
        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}
