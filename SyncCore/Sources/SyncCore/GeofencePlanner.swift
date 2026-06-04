import Foundation

/// A location reminder to monitor: the reminder id + its geofence (AppSpec §5.7 kind 2, P3-7).
public struct LocationReminder: Equatable, Sendable, Identifiable {
    public var id: String
    public var region: ReminderRegion

    public init(id: String, region: ReminderRegion) {
        self.id = id
        self.region = region
    }
}

/// Pure planner that picks which geofences to monitor (P3-7). iOS (CoreLocation) monitors at most 20
/// regions per app, so when the user has more location reminders than the cap we keep the ones nearest
/// to their current location (the most likely to fire soon). With no known location, a stable prefix is
/// kept so the selection doesn't thrash. The CLLocationManager calls are device-bound and live in the
/// app's `LocationReminderService`.
public enum GeofencePlanner {
    /// iOS's hard limit on simultaneously-monitored regions per app.
    public static let systemRegionCap = 20

    public static func plan(
        reminders: [LocationReminder],
        userLocation: GeoPoint?,
        cap: Int = systemRegionCap
    ) -> [LocationReminder] {
        let cap = max(0, cap)
        if reminders.count <= cap { return reminders }
        guard let user = userLocation else { return Array(reminders.prefix(cap)) }
        return reminders
            .sorted { distanceMeters(from: user, to: $0.region.center) < distanceMeters(from: user, to: $1.region.center) }
            .prefix(cap)
            .map { $0 }
    }

    /// Equirectangular-approximation distance in metres — cheap and accurate enough to *rank* nearby
    /// regions (not for navigation). Good to well under a percent at city scale.
    public static func distanceMeters(from a: GeoPoint, to b: GeoPoint) -> Double {
        let earthRadius = 6_371_000.0
        let aLat = a.lat * .pi / 180
        let bLat = b.lat * .pi / 180
        let x = (b.lon - a.lon) * .pi / 180 * cos((aLat + bLat) / 2)
        let y = bLat - aLat
        return (x * x + y * y).squareRoot() * earthRadius
    }
}
