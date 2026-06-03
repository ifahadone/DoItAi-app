import Foundation

/// A geographic point attached to a task (AppSpec §6 `GeoPoint`).
///
/// Stored server-side as JSONB in `tasks.location` (`{ lat, lon, name }`, ApiSpec §5.1).
public struct GeoPoint: Codable, Sendable, Equatable {
    public var lat: Double
    public var lon: Double
    public var name: String?

    public init(lat: Double, lon: Double, name: String? = nil) {
        self.lat = lat
        self.lon = lon
        self.name = name
    }
}
