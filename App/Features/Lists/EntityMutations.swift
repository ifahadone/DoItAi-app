import Foundation
import SwiftData
import SyncCore

/// Create/rename/delete for `list` and `tag` entities (DevelopmentPlan P1-F). Mirrors
/// ``TaskCreation``/``TaskMutation``: write SwiftData immediately, then enqueue a sparse-patch outbox
/// op (only writable columns; the server derives id/owner/timestamps). `baseVersion` is the row's
/// last-seen `serverVersion`.
@MainActor
struct ListMutation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator
    let ownerId: String

    @discardableResult
    func create(name: String, colorHex: String = "#4F46E5", icon: String = "list.bullet") async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = clock.now()
        let id = idGenerator.newID()
        context.insert(TaskListModel(
            id: id, ownerId: ownerId, name: trimmed, colorHex: colorHex, icon: icon,
            sortIndex: 0, createdAt: now, updatedAt: now, serverVersion: 0,
            syncStateRaw: LocalSyncState.pendingCreate.rawValue
        ))
        try? context.save()
        await enqueueUpsert(id: id, baseVersion: 0, fields: [
            "name": .string(trimmed), "colorHex": .string(colorHex),
            "icon": .string(icon), "sortIndex": .int(0),
        ])
        return id
    }

    func rename(_ list: TaskListModel, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != list.name else { return }
        list.name = trimmed
        list.updatedAt = clock.now()
        if list.syncState == .synced { list.syncState = .pendingUpdate }
        try? context.save()
        await enqueueUpsert(id: list.id, baseVersion: list.serverVersion, fields: ["name": .string(trimmed)])
    }

    func delete(_ list: TaskListModel) async {
        let now = clock.now()
        let op = OutboxOp(opId: idGenerator.newID(), entityType: .list, entityId: list.id, op: .delete,
                          baseVersion: list.serverVersion, clientUpdatedAt: now, fields: [:], enqueuedAt: now)
        list.deletedAt = now
        list.syncState = .pendingDelete
        try? context.save()
        await engine.enqueue(op)
    }

    private func enqueueUpsert(id: String, baseVersion: Int, fields: [String: AnyCodable]) async {
        let now = clock.now()
        await engine.enqueue(OutboxOp(opId: idGenerator.newID(), entityType: .list, entityId: id, op: .upsert,
                                      baseVersion: baseVersion, clientUpdatedAt: now, fields: fields, enqueuedAt: now))
    }
}

@MainActor
struct TagMutation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator
    let ownerId: String

    @discardableResult
    func create(name: String, colorHex: String = "#10B981") async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = clock.now()
        let id = idGenerator.newID()
        context.insert(TagModel(
            id: id, ownerId: ownerId, name: trimmed, colorHex: colorHex,
            createdAt: now, updatedAt: now, serverVersion: 0,
            syncStateRaw: LocalSyncState.pendingCreate.rawValue
        ))
        try? context.save()
        let op = OutboxOp(opId: idGenerator.newID(), entityType: .tag, entityId: id, op: .upsert,
                          baseVersion: 0, clientUpdatedAt: now,
                          fields: ["name": .string(trimmed), "colorHex": .string(colorHex)], enqueuedAt: now)
        await engine.enqueue(op)
        return id
    }

    func delete(_ tag: TagModel) async {
        let now = clock.now()
        let op = OutboxOp(opId: idGenerator.newID(), entityType: .tag, entityId: tag.id, op: .delete,
                          baseVersion: tag.serverVersion, clientUpdatedAt: now, fields: [:], enqueuedAt: now)
        tag.deletedAt = now
        tag.syncState = .pendingDelete
        try? context.save()
        await engine.enqueue(op)
    }
}
