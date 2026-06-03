import Foundation

/// The network boundary the ``SyncEngine`` flushes through.
///
/// SyncCore stays framework-free, so it does **not** import URLSession. Instead the app target's
/// `APIClient` actor conforms to this protocol and is injected into ``DefaultSyncEngine/flush(using:)``
/// / ``applyPull(using:)``. Tests provide an in-memory fake. This keeps the engine's queue/retry
/// logic pure and unit-testable (AppSpec §7, §16).
public protocol SyncTransport: Sendable {
    /// Send a batch of outbox ops to `POST /sync/push` and return one result per op (ApiSpec §6.1).
    func push(_ request: SyncPushRequest) async throws -> SyncPushResponse

    /// Fetch deltas from `GET /sync/pull?cursor=…` (ApiSpec §6.2). `cursor` is the opaque
    /// `base64(seq)` from the previous pull, or `nil` for a first full sync.
    func pull(cursor: String?, limit: Int) async throws -> SyncPullResponse
}
