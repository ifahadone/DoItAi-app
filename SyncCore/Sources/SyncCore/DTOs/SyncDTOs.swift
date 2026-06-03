import Foundation

// Wire shapes for the sync protocol (ApiSpec §6). These are the over-the-wire envelopes; the
// durable client-side outbox entry is ``OutboxOp`` (see Sync/OutboxOp.swift), which produces a
// ``SyncPushOp`` when flushed.

// MARK: - Push (client → server)

/// A single mutation in a push batch (`POST /sync/push`, ApiSpec §6.1).
///
/// `fields` is a sparse **patch** of only the changed fields, keyed by the camelCase DTO field name,
/// with type-erased JSON values (``AnyCodable``). `baseVersion` is the `serverVersion` the client
/// last saw (0 for a brand-new entity) and drives conflict detection.
public struct SyncPushOp: Codable, Sendable, Equatable {
    public var opId: String
    public var entityType: SyncEntityType
    public var entityId: String
    public var op: SyncOp
    public var baseVersion: Int
    public var clientUpdatedAt: Date
    public var fields: [String: AnyCodable]

    public init(
        opId: String,
        entityType: SyncEntityType,
        entityId: String,
        op: SyncOp,
        baseVersion: Int,
        clientUpdatedAt: Date,
        fields: [String: AnyCodable]
    ) {
        self.opId = opId
        self.entityType = entityType
        self.entityId = entityId
        self.op = op
        self.baseVersion = baseVersion
        self.clientUpdatedAt = clientUpdatedAt
        self.fields = fields
    }
}

/// The request body for `POST /sync/push`: an ordered batch of ops.
public struct SyncPushRequest: Codable, Sendable, Equatable {
    public var ops: [SyncPushOp]

    public init(ops: [SyncPushOp]) {
        self.ops = ops
    }
}

/// One result per pushed op, returned in the same order (ApiSpec §6.1).
///
/// On `.merged`, `serverFields` carries the fields the server kept (the client lost those); on
/// `.conflict` the op hit a structural conflict (surfaced in the activity log, never dropped).
/// `committedSeq` is the `change_log` seq this change produced and advances the pull cursor.
public struct SyncPushResult: Codable, Sendable, Equatable {
    public var opId: String
    public var entityId: String
    public var status: PushStatus
    public var serverVersion: Int
    public var serverFields: [String: AnyCodable]?
    public var committedSeq: Int

    public init(
        opId: String,
        entityId: String,
        status: PushStatus,
        serverVersion: Int,
        serverFields: [String: AnyCodable]? = nil,
        committedSeq: Int
    ) {
        self.opId = opId
        self.entityId = entityId
        self.status = status
        self.serverVersion = serverVersion
        self.serverFields = serverFields
        self.committedSeq = committedSeq
    }
}

/// The response body from `POST /sync/push`.
public struct SyncPushResponse: Codable, Sendable, Equatable {
    public var results: [SyncPushResult]

    public init(results: [SyncPushResult]) {
        self.results = results
    }
}

// MARK: - Pull (server → client)

/// A single change in a pull delta (ApiSpec §6.2). `payload` is the full row snapshot for an
/// `upsert`, and `nil` for a `delete` (tombstone). `seq` is the monotonic `change_log` cursor value.
///
/// `payload` is kept type-erased here (``AnyCodable``); the SyncEngine decodes it into the concrete
/// DTO (``TaskDTO`` etc.) based on `entityType`. Keeping it erased means a payload for an
/// `entityType` this build doesn't model yet still decodes and can be skipped, not crash.
public struct SyncPullChange: Codable, Sendable, Equatable {
    public var entityType: SyncEntityType
    public var entityId: String
    public var op: SyncOp
    public var version: Int
    public var payload: AnyCodable?
    public var seq: Int

    public init(
        entityType: SyncEntityType,
        entityId: String,
        op: SyncOp,
        version: Int,
        payload: AnyCodable? = nil,
        seq: Int
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.op = op
        self.version = version
        self.payload = payload
        self.seq = seq
    }
}

/// The response body from `GET /sync/pull?cursor=…` (ApiSpec §6.2).
///
/// `nextCursor` is the opaque `base64(maxSeq)` to pass on the next pull; `hasMore == true` means
/// page again immediately.
public struct SyncPullResponse: Codable, Sendable, Equatable {
    public var changes: [SyncPullChange]
    public var nextCursor: String
    public var hasMore: Bool

    public init(changes: [SyncPullChange], nextCursor: String, hasMore: Bool) {
        self.changes = changes
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}
