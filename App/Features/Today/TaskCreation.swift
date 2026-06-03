import Foundation
import SwiftData
import SyncCore

/// Creates tasks locally and enqueues them for sync (AppSpec §8 outbox pattern).
///
/// This is the thin slice of `TaskService` needed for the Phase 0 walking skeleton: a local create
/// that (1) writes a `TaskModel` to SwiftData (instant, offline-first) and (2) enqueues an
/// ``OutboxOp`` so the ``DefaultSyncEngine`` will push it. The full CRUD service lands in Phase 1.
///
/// Time comes from an injected ``Clock`` (no direct `Date()` — AppSpec §16); ids from an
/// ``IDGenerator``. Requires the Xcode app target (SwiftData).
@MainActor
struct TaskCreation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator
    /// The signed-in user's id (owner of created rows). Sourced from auth at call sites.
    let ownerId: String

    init(
        context: ModelContext,
        engine: DefaultSyncEngine,
        ownerId: String,
        clock: Clock = SystemClock(),
        idGenerator: IDGenerator = UUIDGenerator()
    ) {
        self.context = context
        self.engine = engine
        self.ownerId = ownerId
        self.clock = clock
        self.idGenerator = idGenerator
    }

    /// Create a task with `title`, persist it, and enqueue an upsert op. Returns the new id.
    @discardableResult
    func createTask(title: String) async -> String {
        let now = clock.now()
        let id = idGenerator.newID()

        let model = TaskModel(
            id: id,
            ownerId: ownerId,
            title: title,
            statusRaw: TaskStatus.inbox.rawValue,
            createdAt: now,
            updatedAt: now,
            serverVersion: 0,
            syncStateRaw: LocalSyncState.pendingCreate.rawValue
        )
        context.insert(model)
        try? context.save()

        // Enqueue the create as an outbox upsert with baseVersion 0 (brand new). Only the fields the
        // server needs for a create are sent; later edits send sparse patches.
        let op = OutboxOp(
            opId: idGenerator.newID(),
            entityType: .task,
            entityId: id,
            op: .upsert,
            baseVersion: 0,
            clientUpdatedAt: now,
            fields: [
                "id": .string(id),
                "ownerId": .string(ownerId),
                "title": .string(title),
                "status": .int(TaskStatus.inbox.rawValue),
                "priority": .int(Priority.none.rawValue),
                "rank": .int(0),
                "isAllDay": .bool(false),
                "createdAt": .string(Self.iso(now)),
                "updatedAt": .string(Self.iso(now))
            ],
            enqueuedAt: now
        )
        await engine.enqueue(op)
        return id
    }

    /// ISO-8601 (RFC 3339, no fractional seconds) for embedding dates in the AnyCodable field bag.
    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
