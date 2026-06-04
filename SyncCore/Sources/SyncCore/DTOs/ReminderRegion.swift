import Foundation

/// A geofence for a location reminder (`ReminderDTO.region`, ApiSpec §5.7, kind 2). Stored server-side
/// as JSONB. Maps to a `CLCircularRegion` on device; see `GeofencePlanner` for the 20-region cap.
public struct ReminderRegion: Codable, Sendable, Equatable {
    public var center: GeoPoint
    /// Radius in metres (clamped to the device's `maximumRegionMonitoringDistance` at monitor time).
    public var radius: Double
    /// Fire when the user enters the region.
    public var onEntry: Bool
    /// Fire when the user leaves the region.
    public var onExit: Bool

    public init(center: GeoPoint, radius: Double = 100, onEntry: Bool = true, onExit: Bool = false) {
        self.center = center
        self.radius = radius
        self.onEntry = onEntry
        self.onExit = onExit
    }
}
