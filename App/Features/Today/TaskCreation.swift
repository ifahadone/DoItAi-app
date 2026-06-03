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

    /// Create a task with `title` (optionally pre-assigned to `listId`), persist it, and enqueue an
    /// upsert op. Returns the new id.
    @discardableResult
    func createTask(title: String, listId: String? = nil) async -> String {
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
        model.listId = listId
        context.insert(model)
        try? context.save()

        // Enqueue the create as an outbox upsert with baseVersion 0 (brand new). The patch carries
        // ONLY writable task columns (ApiSpec §6.1 / TaskPatchSchema, which is strict): the server
        // derives `id` from the op's entityId, `ownerId` from the auth token, and created/updated
        // timestamps from its own clock — including those here is rejected as `invalid_patch`.
        var fields: [String: AnyCodable] = [
            "title": .string(title),
            "status": .int(TaskStatus.inbox.rawValue),
            "priority": .int(Priority.none.rawValue),
            "rank": .int(0),
            "isAllDay": .bool(false),
        ]
        if let listId { fields["listId"] = .string(listId) }
        let op = OutboxOp(
            opId: idGenerator.newID(),
            entityType: .task,
            entityId: id,
            op: .upsert,
            baseVersion: 0,
            clientUpdatedAt: now,
            fields: fields,
            enqueuedAt: now
        )
        await engine.enqueue(op)
        return id
    }
}
