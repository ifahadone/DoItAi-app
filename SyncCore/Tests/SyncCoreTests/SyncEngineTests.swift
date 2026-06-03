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
