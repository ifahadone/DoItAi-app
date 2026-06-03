import Foundation

/// A durable, retry-safe entry in the client outbox (AppSpec §8 "Outbox pattern").
///
/// Every local mutation enqueues one ``OutboxOp``; the ``SyncEngine`` flushes the queue to
/// `POST /sync/push` with backoff. Because each op carries a stable client-minted `opId`, replays
/// are idempotent server-side (ApiSpec §6.3) — this satisfies the global "background jobs must be
/// retry-safe" rule.
///
/// This is the in-memory / persistable representation; ``toPushOp()`` converts it to the wire shape
/// ``SyncPushOp``. Persistence (e.g. a SwiftData-backed outbox table) lives in the app target; this
/// type stays framework-free so the queue logic is unit-testable.
public struct OutboxOp: Codable, Sendable, Equatable, Identifiable {
    /// Stable client UUID; the server dedupe key for retries.
    public var opId: String
    public var entityType: SyncEntityType
    public var entityId: String
    public var op: SyncOp
    /// The `serverVersion` the client last saw for this entity (0 for a brand-new create).
    public var baseVersion: Int
    /// When the client made this change, in UTC — drives field-level LWW (sourced from a `Clock`).
    public var clientUpdatedAt: Date
    /// Sparse patch of changed fields (camelCase DTO keys → type-erased values).
    public var fields: [String: AnyCodable]

    // --- Local bookkeeping (not sent on the wire) ---

    /// Number of flush attempts so far; used for backoff and poison-message handling.
    public var attemptCount: Int
    /// When this op was first enqueued (UTC), for ordering and age-based diagnostics.
    public var enqueuedAt: Date

    /// `id` for `Identifiable` is the `opId`.
    public var id: String { opId }

    public init(
        opId: String,
        entityType: SyncEntityType,
        entityId: String,
        op: SyncOp,
        baseVersion: Int,
        clientUpdatedAt: Date,
        fields: [String: AnyCodable],
        attemptCount: Int = 0,
        enqueuedAt: Date
    ) {
        self.opId = opId
        self.entityType = entityType
        self.entityId = entityId
        self.op = op
        self.baseVersion = baseVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.fields = fields
        self.attemptCount = attemptCount
        self.enqueuedAt = enqueuedAt
    }

    /// Project this durable op into the over-the-wire push op (drops local bookkeeping).
    public func toPushOp() -> SyncPushOp {
        SyncPushOp(
            opId: opId,
            entityType: entityType,
            entityId: entityId,
            op: op,
            baseVersion: baseVersion,
            clientUpdatedAt: clientUpdatedAt,
            fields: fields
        )
    }
}
