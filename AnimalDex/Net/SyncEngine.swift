import CoreLocation
import Foundation
import SwiftData
import UIKit
import os

/// Pushes shared catches up and pulls community sightings down.
///
/// **Offline-first, opt-in.** The SwiftData store is the source of truth and the
/// game is fully playable with no account at all. Nothing is uploaded unless the
/// user marks a specific catch as shared — there is no bulk sync of the dex.
@MainActor
@Observable
final class SyncEngine {

    private let session: SessionStore
    private let log = Logger(subsystem: "com.abhay.animaldex", category: "sync")

    private(set) var communityCatches: [CatchDTO] = []
    private(set) var isSyncing = false
    var errorMessage: String?

    init(session: SessionStore) {
        self.session = session
    }

    /// Publish one catch: photo first, then the record that references it.
    ///
    /// Ordering matters. If the photo upload fails we simply stop, and the catch
    /// stays local and unshared. Creating the catch first would leave a shared
    /// sighting pointing at media that never arrived.
    func share(_ record: CatchRecord, species: Species, context: ModelContext) async {
        guard session.isSignedIn else {
            errorMessage = "Sign in to share catches."
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        do {
            var mediaId: UUID?

            if let image = PhotoStore.shared.load(record.photoFilename),
               let data = image.jpegData(compressionQuality: 0.8) {
                let ticket = try await session.client.requestUploadURL(
                    contentType: "image/jpeg", byteSize: data.count
                )
                try await session.client.uploadImageData(
                    data, to: ticket.uploadUrl, contentType: "image/jpeg"
                )
                _ = try await session.client.completeUpload(mediaId: ticket.mediaId)
                mediaId = ticket.mediaId
            }

            // The single point where a coordinate is transformed before leaving
            // the device.
            let published = LocationPrivacy.obscuredCoordinate(
                for: record.coordinate, rarity: species.rarity
            )

            let created = try await session.client.createCatch(
                CreateCatchDTO(
                    speciesKey: record.speciesKey,
                    caughtAt: record.capturedAt,
                    lat: published?.latitude,
                    lng: published?.longitude,
                    confidence: record.confidence,
                    mediaId: mediaId
                )
            )

            record.isSharedToCommunity = true
            record.remoteID = created.id
            try context.save()
            errorMessage = nil
            log.info("shared catch \(record.speciesKey, privacy: .public)")
        } catch {
            errorMessage = error.localizedDescription
            log.error("share failed: \(error.localizedDescription)")
        }
    }

    /// Community sightings around a point.
    func refreshCommunity(around coordinate: CLLocationCoordinate2D, radiusM: Double = 25_000) async {
        guard session.isSignedIn else {
            communityCatches = []
            return
        }
        do {
            communityCatches = try await session.client.nearby(
                lat: coordinate.latitude, lng: coordinate.longitude, radiusM: radiusM
            )
        } catch {
            // A failed community refresh must not disturb the map: the user's own
            // pins are local and still perfectly valid.
            log.error("community refresh failed: \(error.localizedDescription)")
        }
    }
}
