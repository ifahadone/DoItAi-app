import Foundation
import CoreLocation
import SyncCore

/// Monitors geofences for location reminders (AppSpec §5.7 kind 2, P3-7).
///
/// **Device-bound.** Region monitoring needs *Always* location authorization (a system prompt) and a
/// real device feeding location. iOS monitors at most 20 regions per app — which 20 to keep is decided
/// by the pure, tested ``SyncCore/GeofencePlanner`` (nearest to the user); only the
/// `CLLocationManager` calls here need a device. The app's Info.plist must carry
/// `NSLocationAlwaysAndWhenInUseUsageDescription` + `NSLocationWhenInUseUsageDescription`.
@MainActor
final class LocationReminderService: NSObject {
    private let manager = CLLocationManager()
    private let identifierPrefix = "locrem-"

    /// Region monitoring requires Always authorization (it fires in the background).
    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    /// Re-arm geofence monitoring: stop our existing regions, then monitor the planned ≤20 nearest the
    /// user. Returns how many regions are now monitored. The selection is pure/tested; the monitoring is
    /// device-bound (no-op without authorization on a device).
    @discardableResult
    func rearm(_ reminders: [LocationReminder], userLocation: GeoPoint?) -> Int {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(identifierPrefix) {
            manager.stopMonitoring(for: region)
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return 0 }

        let maxRadius = manager.maximumRegionMonitoringDistance
        let plan = GeofencePlanner.plan(reminders: reminders, userLocation: userLocation)
        var count = 0
        for item in plan {
            let radius = maxRadius > 0 ? min(item.region.radius, maxRadius) : item.region.radius
            let center = CLLocationCoordinate2D(latitude: item.region.center.lat, longitude: item.region.center.lon)
            let region = CLCircularRegion(center: center, radius: radius, identifier: identifierPrefix + item.id)
            region.notifyOnEntry = item.region.onEntry
            region.notifyOnExit = item.region.onExit
            manager.startMonitoring(for: region)
            count += 1
        }
        return count
    }

    /// How many of our geofences are currently monitored (≤ 20). Used to verify the re-arm.
    func monitoredCount() -> Int {
        manager.monitoredRegions.filter { $0.identifier.hasPrefix(identifierPrefix) }.count
    }
}
