import Foundation

/// Generates the client-side UUID string ids used for every entity (AppSpec §6, ApiSpec §3).
///
/// IDs are minted on the client so an offline create survives sync with no server remap. Modeled as
/// a protocol so tests can inject a deterministic sequence instead of random UUIDs.
public protocol IDGenerator: Sendable {
    /// A fresh, unique identifier (canonical lowercase UUID v4 string by convention).
    func newID() -> String
}

/// The production generator: a random UUID v4, lowercased to match the server's canonical form.
public struct UUIDGenerator: IDGenerator {
    public init() {}

    public func newID() -> String {
        UUID().uuidString.lowercased()
    }
}
