import CoreLocation
import os

/// One-shot location fixes for catches.
///
/// Deliberately *not* continuous tracking: a nature app has no reason to follow
/// you around, and a single fix at the moment of capture is all a map pin needs.
@MainActor
@Observable
final class LocationProvider: NSObject {

    private(set) var authorization: CLAuthorizationStatus
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    private let log = Logger(subsystem: "com.abhay.animaldex", category: "location")

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestAuthorization() {
        guard authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Returns nil rather than throwing: a catch without a location is still a
    /// perfectly good catch, it just won't appear on the map.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        guard authorization == .authorizedWhenInUse || authorization == .authorizedAlways else {
            return nil
        }
        if let existing = continuation {
            existing.resume(returning: nil)
            continuation = nil
        }
        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        Task { @MainActor in self.finish(coord) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.log.error("location failed: \(error.localizedDescription)")
            self.finish(nil)
        }
    }
}
