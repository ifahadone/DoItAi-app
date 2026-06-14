import XCTest
@testable import SyncCore

// MARK: - Test doubles

/// An in-memory transport that records what was pushed and returns scripted responses.
private actor FakeTransport: SyncTransport {
    private(set) var pushedBatches: [SyncPushRequest] = []
    private(set) var pullCursors: [String?] = []
    var pushResponder: (@Sendable (SyncPushRequest) -> SyncPushResponse)?
    var pullResponder: (@Sendable (String?) -> SyncPullResponse)?

    func setPushResponder(_ responder: @escaping @Sendable (SyncPushRequest) -> SyncPushResponse) {
        pushResponder = responder
    }
    func setPullResponder(_ responder: @escaping @Sendable (String?) -> SyncPullResponse) {
        pullResponder = responder
    }

    func push(_ request: SyncPushRequest) async throws -> SyncPushResponse {
        pushedBatches.append(request)
        return pushResponder?(request) ?? SyncPushResponse(results: [])
    }

    func pull(cursor: String?, limit: Int) async throws -> SyncPullResponse {
        pullCursors.append(cursor)
        return pullResponder?(cursor) ?? SyncPullResponse(changes: [], nextCursor: cursor ?? "", hasMore: false)
    }
}

/// A store that records the changes the engine applied.
private actor RecordingStore: SyncStore {
    private(set) var applied: [SyncPullChange] = []
    func apply(_ change: SyncPullChange) async throws {
        applied.append(change)
    }
}

private struct DecodeError: Error {}

/// A store that throws for changes whose entityId is in `failIds` (simulating an undecodable payload),
/// and records the rest — to prove one bad change doesn't abort the whole pull.
private actor SelectivelyFailingStore: SyncStore {
    let failIds: Set<String>
    private(set) var applied: [SyncPullChange] = []
    init(failIds: Set<String>) { self.failIds = failIds }
    func apply(_ change: SyncPullChange) async throws {
        if failIds.contains(change.entityId) { throw DecodeError() }
        applied.append(change)
    }
}

/// Records every persisted snapshot so tests can assert the durable queue/cursor track engine state.
/// `save` is synchronous (per the protocol) and called from the engine actor, so an NSLock guards the
/// recorded saves against the test thread reading concurrently.
private final class RecordingPersister: SyncStatePersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var saves: [(outbox: [OutboxOp], cursor: String?)] = []

    func save(outbox: [OutboxOp], cursor: String?) {
        lock.lock(); defer { lock.unlock() }
        saves.append((outbox, cursor))
    }
    var saveCount: Int { lock.lock(); defer { lock.unlock() }; return saves.count }
    var lastOutboxIds: [String] { lock.lock(); defer { lock.unlock() }; return saves.last?.outbox.map(\.opId) ?? [] }
    var lastCursor: String? { lock.lock(); defer { lock.unlock() }; return saves.last.flatMap { $0.cursor } }
}

// MARK: - Tests

final class SyncEngineTests: XCTestCase {
    private let clock = FixedClock(Date(timeIntervalSince1970: 1_000))

    private func makeOp(id: String, entity: String = "task") -> OutboxOp {
        OutboxOp(
            opId: id,
            entityType: .task,
            entityId: entity,
            op: .upsert,
            baseVersion: 0,
            clientUpdatedAt: clock.now(),
            fields: ["title": .string("T-\(id)")],
            enqueuedAt: clock.now()
        )
    }

    func testEnqueueIncrementsPendingCount() async {
        let engine = DefaultSyncEngine(clock: clock)
        await engine.enqueue(makeOp(id: "1"))
        await engine.enqueue(makeOp(id: "2"))
        let count = await engine.pendingCount
        XCTAssertEqual(count, 2)
    }

    func testFlushSendsBatchAndRemovesAcknowledgedOps() async throws {
        let engine = DefaultSyncEngine(clock: clock)
        await engine.enqueue(makeOp(id: "1"))
        await engine.enqueue(makeOp(id: "2"))

        let transport = FakeTransport()
        await transport.setPushResponder { request in
            // Acknowledge op 1 as applied; op 2 as rejected (must stay in the outbox).
            let results = request.ops.map { op -> SyncPushResult in
                let status: PushStatus = op.opId == "1" ? .applied : .rejected
                return SyncPushResult(opId: op.opId, entityId: op.entityId, status: status, serverVersion: 1, committedSeq: "10")
            }
            return SyncPushResponse(results: results)
        }

        let results = try await engine.flush(using: transport)
        XCTAssertEqual(results.count, 2)

        let pending = await engine.pendingCount
        XCTAssertEqual(pending, 1) // op 2 (rejected) remains

        let batches = await transport.pushedBatches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].ops.count, 2)
    }

    func testFlushOnEmptyOutboxIsNoOp() async throws {
        let engine = DefaultSyncEngine(clock: clock)
        let transport = FakeTransport()
        let results = try await engine.flush(using: transport)
        XCTAssertTrue(results.isEmpty)
        let batches = await transport.pushedBatches
        XCTAssertTrue(batches.isEmpty)
    }

    func testApplyPullAppliesChangesAndAdvancesCursor() async throws {
        let store = RecordingStore()
        let engine = DefaultSyncEngine(clock: clock, store: store)

        let transport = FakeTransport()
        await transport.setPullResponder { _ in
            SyncPullResponse(
                changes: [
                    SyncPullChange(entityType: .task, entityId: "a", op: .upsert,
                                   version: 1, payload: .object(["id": .string("a")]), seq: "5"),
                    SyncPullChange(entityType: .task, entityId: "b", op: .delete, version: 2, seq: "6")
                ],
                nextCursor: "Ng==",
                hasMore: false
            )
        }

        let applied = try await engine.applyPull(using: transport)
        XCTAssertEqual(applied, 2)

        let cursor = await engine.currentCursor
        XCTAssertEqual(cursor, "Ng==")

        let recorded = await store.applied
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(recorded[0].entityId, "a")
        XCTAssertEqual(recorded[1].op, .delete)
    }

    func testApplyPullStartsFromInitialCursor() async throws {
        let engine = DefaultSyncEngine(clock: clock, initialCursor: "start")
        let transport = FakeTransport()
        await transport.setPullResponder { cursor in
            SyncPullResponse(changes: [], nextCursor: cursor ?? "", hasMore: false)
        }
        _ = try await engine.applyPull(using: transport)
        let cursors = await transport.pullCursors
        XCTAssertEqual(cursors, ["start"])
    }

    func testApplyPullPagesUntilHasMoreFalse() async throws {
        let store = RecordingStore()
        let engine = DefaultSyncEngine(clock: clock, store: store)
        let transport = FakeTransport()
        // Page 1 (initial cursor nil) → hasMore; page 2 (cursor "p2") → done.
        await transport.setPullResponder { cursor in
            if cursor == "p2" {
                return SyncPullResponse(
                    changes: [SyncPullChange(entityType: .task, entityId: "c", op: .upsert, version: 3, seq: "3")],
                    nextCursor: "p3", hasMore: false)
            }
            return SyncPullResponse(
                changes: [
                    SyncPullChange(entityType: .task, entityId: "a", op: .upsert, version: 1, seq: "1"),
                    SyncPullChange(entityType: .task, entityId: "b", op: .upsert, version: 2, seq: "2"),
                ],
                nextCursor: "p2", hasMore: true)
        }

        let applied = try await engine.applyPull(using: transport)
        XCTAssertEqual(applied, 3, "should apply both pages, not just the first")
        let cursors = await transport.pullCursors
        XCTAssertEqual(cursors, [nil, "p2"], "should request page 2 with the advanced cursor, then stop")
        let finalCursor = await engine.currentCursor
        XCTAssertEqual(finalCursor, "p3")
        let recorded = await store.applied
        XCTAssertEqual(recorded.map(\.entityId), ["a", "b", "c"])
    }

    func testApplyPullSkipsUndecodableChangeWithoutAborting() async throws {
        let store = SelectivelyFailingStore(failIds: ["bad"])
        let engine = DefaultSyncEngine(clock: clock, store: store)
        let transport = FakeTransport()
        await transport.setPullResponder { _ in
            SyncPullResponse(
                changes: [
                    SyncPullChange(entityType: .task, entityId: "ok1", op: .upsert, version: 1, seq: "1"),
                    SyncPullChange(entityType: .routine, entityId: "bad", op: .upsert, version: 2, seq: "2"),
                    SyncPullChange(entityType: .task, entityId: "ok2", op: .upsert, version: 3, seq: "3"),
                ],
                nextCursor: "done", hasMore: false)
        }

        let applied = try await engine.applyPull(using: transport)
        XCTAssertEqual(applied, 2, "the undecodable change is skipped, the other two apply")
        let recorded = await store.applied
        XCTAssertEqual(recorded.map(\.entityId), ["ok1", "ok2"], "good changes survive a bad one")
        let cursor = await engine.currentCursor
        XCTAssertEqual(cursor, "done", "cursor still advances — no infinite retry on the bad change")
    }

    func testLoadAndSnapshotOutbox() async {
        let engine = DefaultSyncEngine(clock: clock)
        await engine.loadOutbox([makeOp(id: "1"), makeOp(id: "2")])
        let snapshot = await engine.snapshotOutbox()
        XCTAssertEqual(snapshot.map(\.opId), ["1", "2"])
    }

    /// flush() must drop every terminal status (applied/merged/duplicate/conflict) from the outbox —
    /// crucially `.conflict`, which would otherwise re-conflict on every flush — while KEEPING
    /// `.rejected`, and surface merged/conflict outcomes to the caller (never silently lost).
    func testFlushReconcilesAllStatuses() async throws {
        let engine = DefaultSyncEngine(clock: clock)
        for id in ["applied", "merged", "conflict", "duplicate", "rejected"] {
            await engine.enqueue(makeOp(id: id))
        }

        let transport = FakeTransport()
        await transport.setPushResponder { request in
            SyncPushResponse(results: request.ops.map { op in
                let status: PushStatus
                var serverFields: [String: AnyCodable]?
                switch op.opId {
                case "applied": status = .applied
                case "merged": status = .merged; serverFields = ["title": .string("server-wins")]
                case "conflict": status = .conflict
                case "duplicate": status = .duplicate
                default: status = .rejected
                }
                return SyncPushResult(opId: op.opId, entityId: op.entityId, status: status,
                                      serverVersion: 2, serverFields: serverFields, committedSeq: "99")
            })
        }

        let results = try await engine.flush(using: transport)
        XCTAssertEqual(results.count, 5) // all surfaced to the caller

        // Only the rejected op remains queued.
        let pending = await engine.snapshotOutbox().map(\.opId)
        XCTAssertEqual(pending, ["rejected"])

        // Merged carries the server-kept fields; conflict is present (surfaced), not dropped silently.
        XCTAssertEqual(results.first { $0.status == .merged }?.serverFields?["title"], .string("server-wins"))
        XCTAssertTrue(results.contains { $0.status == .conflict })
    }

    /// The Phase 0 walking-skeleton loop end-to-end: enqueue a local create → flush (server accepts,
    /// outbox drains) → pull (the authoritative row comes back and is applied to the local store,
    /// cursor advances).
    func testFullEnqueueFlushPullCycle() async throws {
        let store = RecordingStore()
        let engine = DefaultSyncEngine(clock: clock, store: store)

        await engine.enqueue(makeOp(id: "op1", entity: "task-1"))
        let pendingBefore = await engine.pendingCount
        XCTAssertEqual(pendingBefore, 1)

        let transport = FakeTransport()
        await transport.setPushResponder { request in
            SyncPushResponse(results: request.ops.map {
                SyncPushResult(opId: $0.opId, entityId: $0.entityId, status: .applied,
                               serverVersion: 1, committedSeq: "7")
            })
        }
        await transport.setPullResponder { _ in
            SyncPullResponse(
                changes: [SyncPullChange(entityType: .task, entityId: "task-1", op: .upsert, version: 1,
                                         payload: .object(["id": .string("task-1"), "title": .string("T-op1")]),
                                         seq: "7")],
                nextCursor: "Nw==", hasMore: false
            )
        }

        let pushResults = try await engine.flush(using: transport)
        XCTAssertEqual(pushResults.first?.status, .applied)
        let pendingAfter = await engine.pendingCount
        XCTAssertEqual(pendingAfter, 0) // outbox drained

        let applied = try await engine.applyPull(using: transport)
        XCTAssertEqual(applied, 1)
        let recorded = await store.applied
        XCTAssertEqual(recorded.map(\.entityId), ["task-1"])
        let cursor = await engine.currentCursor
        XCTAssertEqual(cursor, "Nw==")
    }

    // MARK: Durable outbox + cursor persistence (AppSpec §8)

    func testEnqueuePersistsOutbox() async {
        let persister = RecordingPersister()
        let engine = DefaultSyncEngine(clock: clock, persister: persister)
        await engine.enqueue(makeOp(id: "1"))
        await engine.enqueue(makeOp(id: "2"))
        XCTAssertEqual(persister.lastOutboxIds, ["1", "2"], "every enqueue persists the full queue")
        XCTAssertNil(persister.lastCursor)
    }

    func testFlushPersistsReducedQueue() async throws {
        let persister = RecordingPersister()
        let engine = DefaultSyncEngine(clock: clock, persister: persister)
        await engine.enqueue(makeOp(id: "a"))
        await engine.enqueue(makeOp(id: "b"))

        let transport = FakeTransport()
        await transport.setPushResponder { request in
            SyncPushResponse(results: request.ops.map { op in
                // "a" sticks (rejected); "b" drains (applied).
                SyncPushResult(opId: op.opId, entityId: op.entityId,
                               status: op.opId == "a" ? .rejected : .applied,
                               serverVersion: 1, committedSeq: "5")
            })
        }
        _ = try await engine.flush(using: transport)
        XCTAssertEqual(persister.lastOutboxIds, ["a"], "the durable queue keeps only the rejected op after flush")
    }

    func testPullPersistsCursor() async throws {
        let persister = RecordingPersister()
        let engine = DefaultSyncEngine(clock: clock, persister: persister)
        let transport = FakeTransport()
        await transport.setPullResponder { _ in
            SyncPullResponse(changes: [], nextCursor: "MTA=", hasMore: false)
        }
        _ = try await engine.applyPull(using: transport)
        XCTAssertEqual(persister.lastCursor, "MTA=", "the advanced cursor is checkpointed for resume-after-relaunch")
    }

    func testRestoreRehydratesQueueAndCursorOnce() async {
        let engine = DefaultSyncEngine(clock: clock)
        await engine.restore(outbox: [makeOp(id: "1"), makeOp(id: "2")], cursor: "saved")
        let pending = await engine.pendingCount
        let cursor = await engine.currentCursor
        XCTAssertEqual(pending, 2)
        XCTAssertEqual(cursor, "saved")

        // A second restore is ignored (rehydration is once-per-process).
        await engine.restore(outbox: [makeOp(id: "3")], cursor: "other")
        let pendingAfter = await engine.snapshotOutbox().map(\.opId)
        XCTAssertEqual(pendingAfter, ["1", "2"], "restore is idempotent — the second call is a no-op")
    }

    func testRestorePrependsAndDedupesAgainstStartupEnqueues() async {
        let engine = DefaultSyncEngine(clock: clock)
        // An op enqueued during startup, before the persisted queue is rehydrated.
        await engine.enqueue(makeOp(id: "2"))
        // Persisted queue includes a NEW op "1" and a duplicate of "2".
        await engine.restore(outbox: [makeOp(id: "1"), makeOp(id: "2")], cursor: "c")
        let ids = await engine.snapshotOutbox().map(\.opId)
        XCTAssertEqual(ids, ["1", "2"], "persisted ops prepend ahead of startup enqueues, de-duped by opId")
        // The in-memory cursor (nil here) is replaced by the saved one since none had advanced yet.
        let cursor = await engine.currentCursor
        XCTAssertEqual(cursor, "c")
    }

    func testNoPersisterIsInert() async {
        // The default (no persister) path must behave exactly as before — purely in-memory.
        let engine = DefaultSyncEngine(clock: clock)
        await engine.enqueue(makeOp(id: "1"))
        let pending = await engine.pendingCount
        XCTAssertEqual(pending, 1)
    }

    // MARK: Backoff policy (pure math)

    func testBackoffGrowsExponentiallyAndCaps() {
        let policy = SyncBackoffPolicy(baseDelay: 1, maxDelay: 30, maxAttempts: 8)
        XCTAssertEqual(policy.delay(forAttempt: 0), 1)
        XCTAssertEqual(policy.delay(forAttempt: 1), 2)
        XCTAssertEqual(policy.delay(forAttempt: 2), 4)
        XCTAssertEqual(policy.delay(forAttempt: 3), 8)
        XCTAssertEqual(policy.delay(forAttempt: 4), 16)
        XCTAssertEqual(policy.delay(forAttempt: 5), 30) // capped at maxDelay
        XCTAssertEqual(policy.delay(forAttempt: 50), 30)
    }
}
