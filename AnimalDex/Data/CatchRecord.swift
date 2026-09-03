import Foundation
import SwiftData
import CoreLocation

/// One registered catch. The local store is the source of truth: the app is
/// fully playable offline, and syncing to the backend is opt-in per catch.
@Model
final class CatchRecord {
    // No #Index: that macro is iOS 18+, and this app targets 17.0 so it runs on
    // more phones. At dex scale (137 species, catches in the hundreds) SwiftData's
    // unindexed fetches are not a bottleneck — revisit only if profiling says so.

    var id: UUID = UUID()
    var speciesKey: String = ""
    var capturedAt: Date = Date()

    var latitude: Double?
    var longitude: Double?

    /// Filename within the photo store — never the image bytes. Blobs here would
    /// bloat the store and slow every entries query that only needs metadata.
    var photoFilename: String = ""

    var confidence: Float = 0
    var wasCaptive: Bool = false

    /// Nothing leaves the device unless the user says so per catch.
    var isSharedToCommunity: Bool = false
    /// Set once the backend has accepted it.
    var remoteID: UUID?

    init(
        speciesKey: String,
        capturedAt: Date = .now,
        coordinate: CLLocationCoordinate2D? = nil,
        photoFilename: String,
        confidence: Float,
        wasCaptive: Bool = false
    ) {
        self.id = UUID()
        self.speciesKey = speciesKey
        self.capturedAt = capturedAt
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.photoFilename = photoFilename
        self.confidence = confidence
        self.wasCaptive = wasCaptive
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
