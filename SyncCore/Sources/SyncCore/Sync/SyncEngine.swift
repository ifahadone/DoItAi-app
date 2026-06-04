import Foundation

/// The client side of DoIT's offline-first sync loop (AppSpec §8, ApiSpec §6).
///
/// Responsibilities (Phase 0 = skeleton; the real reconciliation lands in Phase 1):
/// - hold the durable outbox queue of local mutations,
/// - flush it to the server with idempotency + backoff,
/// - apply pulled deltas back into the local store.
///
/// The protocol is the seam the app's services depend on; ``DefaultSyncEngine`` is the actor that
/// implements it. The local persistence write-back is delegated to a ``SyncStore`` so the engine
/// stays free of SwiftData.
public protocol SyncEngine: Actor {
    /// Enqueue a local mutation into the outbox. Returns the op that was stored.
    @discardableResult
    func enqueue(_ op: OutboxOp) -> OutboxOp

    /// Current count of pending outbox ops (primarily for diagnostics/tests).
    var pendingCount: Int { get }

    /// Flush the outbox to the server through `transport`. Returns the per-op results.
    func flush(using transport: SyncTransport) async throws -> [SyncPushResult]

    /// Pull deltas from the server and apply them locally. Returns the number of changes applied.
    @discardableResult
    func applyPull(using transport: SyncTransport) async throws -> Int
}

/// The local-store write-back boundary for applying pulled changes.
///
/// Like ``SyncTransport`` for the network, this keeps the engine free of SwiftData: the app target
/// provides a `SyncStore` that upserts/tombstones decoded entities into the SwiftData container.
public protocol SyncStore: Sendable {
    /// Apply a single decoded change (upsert with `payload`, or delete when `payload == nil`).
    func apply(_ change: SyncPullChange) async throws
}

/// Tuning for retry/backoff. Pure values so backoff math is testable with a fixed clock.
public struct SyncBackoffPolicy: Sendable, Equatable {
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval
    public var maxAttempts: Int

    public init(baseDelay: TimeInterval = 1, maxDelay: TimeInterval = 60, maxAttempts: Int = 8) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
    }

    /// Exponential backoff (no jitter — the engine adds jitter at the call site) for `attempt`
    /// (0-based). Pure and deterministic so it can be unit-tested.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2, Double(max(0, attempt)))
        return min(exponential, maxDelay)
    }
}

/// Actor implementation of ``SyncEngine``. Holds the outbox queue and pull cursor; all mutation of
/// that state is actor-isolated, so the engine is safe to share across the app's services.
public actor DefaultSyncEngine: SyncEngine {
    /// FIFO outbox of pending mutations. Ordered by enqueue time so dependent creates precede edits.
    private var outbox: [OutboxOp] = []
    /// The opaque pull cursor (`base64(seq)`); `nil` until the first successful pull.
    private var cursor: String?
    private let clock: Clock
    private let store: SyncStore?
    private let resolver: ConflictResolver
    private let backoff: SyncBackoffPolicy

    public init(
        clock: Clock = SystemClock(),
        store: SyncStore? = nil,
        resolver: ConflictResolver = ConflictResolver(),
        backoff: SyncBackoffPolicy = SyncBackoffPolicy(),
        initialCursor: String? = nil
    ) {
        self.clock = clock
        self.store = store
        self.resolver = resolver
        self.backoff = backoff
        self.cursor = initialCursor
    }

    public var pendingCount: Int { outbox.count }

    /// The current pull cursor, exposed for persistence/diagnostics.
    public var currentCursor: String? { cursor }

    // MARK: enqueue

    @discardableResult
    public func enqueue(_ op: OutboxOp) -> OutboxOp {
        // TODO(Phase 1): coalesce consecutive upserts for the same entityId into a single op
        //   (merge field patches, keep the latest clientUpdatedAt) so the outbox doesn't grow
        //   unbounded under rapid edits. For now we append verbatim, preserving order.
        // TODO(Phase 1): persist the outbox (SwiftData/file) so it survives app relaunch — the
        //   queue is the source of unsynced work and must be durable (AppSpec §8).
        outbox.append(op)
        return op
    }

    // MARK: flush

    public func flush(using transport: SyncTransport) async throws -> [SyncPushResult] {
        guard !outbox.isEmpty else { return [] }

        // Snapshot the batch we're flushing. New enqueues during the await are handled next flush.
        let batch = outbox
        let request = SyncPushRequest(ops: batch.map { $0.toPushOp() })

        // TODO(Phase 1): wrap this call in retry-with-backoff using `backoff` + a jittered sleep,
        //   bumping `attemptCount` per op and parking poison ops after `maxAttempts`. The network
        //   call itself must carry an `Idempotency-Key` (added by the APIClient) so retries are safe
        //   (ApiSpec §6.3). Backoff is intentionally NOT applied here yet to keep Phase 0 a skeleton.
        let response = try await transport.push(request)

        // Reconcile each result with the outbox (ApiSpec §6.1). The authoritative server state for
        // every accepted op arrives on the next applyPull — pull is the single write-of-truth — so
        // here we only decide what stays queued:
        //   - applied / duplicate → done; drop the op.
        //   - merged              → the server kept some fields (returned in `serverFields`); the
        //                           reconciled row is pulled next. Drop the op; the outcome is
        //                           surfaced to the caller via the returned results.
        //   - conflict            → structural conflict; the server's decision stands and is pulled.
        //                           Drop the op, but it is SURFACED (returned results / activity log)
        //                           so it is never silently lost. (Previously left queued ⇒ it would
        //                           re-conflict on every flush.)
        //   - rejected            → auth / permission / validation failure the caller must address;
        //                           keep it queued rather than dropping or blindly retrying.
        // Only ops from THIS batch are touched; anything enqueued during the await stays put.
        // TODO(Phase 1): apply `serverFields` locally on .merged for instant UI; advance the pull
        //   cursor past max(committedSeq) to skip re-pulling our own writes; add retry/backoff +
        //   poison-parking for rejected ops.
        let batchIds = Set(batch.map(\.opId))
        let keepQueued: Set<String> = Set(
            response.results.filter { $0.status == .rejected }.map(\.opId)
        )
        outbox.removeAll { batchIds.contains($0.opId) && !keepQueued.contains($0.opId) }

        return response.results
    }

    // MARK: applyPull

    @discardableResult
    public func applyPull(using transport: SyncTransport) async throws -> Int {
        var applied = 0
        var pageCursor = cursor

        // Page until the server reports no more deltas (ApiSpec §6.2). Terminate on `hasMore`, NOT on
        // `nextCursor` — the server returns `nextCursor = base64(maxSeq)` which stays non-null at the
        // end, so a `while (cursor)` loop would re-fetch the final page forever. The cursor advances
        // per page so an interrupted pull resumes cleanly.
        while true {
            let response = try await transport.pull(cursor: pageCursor, limit: 500)

            for change in response.changes {
                // Apply each change defensively. A single undecodable/unknown change (e.g. an old
                // payload missing a field a newer build expects) is SKIPPED — not thrown — so it can't
                // abort the whole pull and wedge the cursor into an infinite retry. The per-DTO lenient
                // decoders handle additive fields (ApiSpec §13); this is the backstop for the rest.
                if let store {
                    do {
                        try await store.apply(change)
                        applied += 1
                    } catch {
                        #if DEBUG
                        print("[SyncEngine] skipped undecodable change \(change.entityType)/\(change.entityId): \(error)")
                        #endif
                    }
                } else {
                    applied += 1
                }
            }

            pageCursor = response.nextCursor
            cursor = pageCursor
            if !response.hasMore { break }
        }
        return applied
    }

    // MARK: - Testing / wiring helpers

    /// Replace the outbox wholesale (e.g. when rehydrating a persisted queue at launch).
    public func loadOutbox(_ ops: [OutboxOp]) {
        outbox = ops
    }

    /// Snapshot the current outbox (read-only copy) for persistence or inspection.
    public func snapshotOutbox() -> [OutboxOp] {
        outbox
    }
}
