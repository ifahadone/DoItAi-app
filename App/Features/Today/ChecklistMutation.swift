import Foundation
import SwiftData
import SyncCore

/// Create/toggle/edit/delete checklist (sub-task) items under a task (AppSpec §5.7). Checklist items
/// sync like any entity (`entityType: .checklist`; server upsertable columns: taskId/text/done/ord).
/// Previously the app only consumed inbound checklist pulls — this adds the outbound write path.
@MainActor
struct ChecklistMutation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator
    let ownerId: String

    @discardableResult
    func create(taskId: String, text: String, ord: Int) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = clock.now()
        let id = idGenerator.newID()
        context.insert(ChecklistItemModel(
            id: id, ownerId: ownerId, taskId: taskId, text: trimmed, done: false, ord: ord,
            createdAt: now, updatedAt: now, serverVersion: 0,
            syncStateRaw: LocalSyncState.pendingCreate.rawValue))
        try? context.save()
        await enqueueUpsert(id: id, baseVersion: 0, fields: [
            "taskId": .string(taskId), "text": .string(trimmed), "done": .bool(false), "ord": .int(ord),
        ])
        return id
    }

    func toggle(_ item: ChecklistItemModel) async {
        item.done.toggle()
        touch(item)
        await enqueueUpsert(id: item.id, baseVersion: item.serverVersion, fields: ["done": .bool(item.done)])
    }

    func setText(_ item: ChecklistItemModel, _ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.text else { return }
        item.text = trimmed
        touch(item)
        await enqueueUpsert(id: item.id, baseVersion: item.serverVersion, fields: ["text": .string(trimmed)])
    }

    func delete(_ item: ChecklistItemModel) async {
        let now = clock.now()
        let op = OutboxOp(opId: idGenerator.newID(), entityType: .checklist, entityId: item.id, op: .delete,
                          baseVersion: item.serverVersion, clientUpdatedAt: now, fields: [:], enqueuedAt: now)
        item.deletedAt = now
        item.syncState = .pendingDelete
        try? context.save()
        await engine.enqueue(op)
    }

    private func touch(_ item: ChecklistItemModel) {
        item.updatedAt = clock.now()
        if item.syncState == .synced { item.syncState = .pendingUpdate }
        try? context.save()
    }

    private func enqueueUpsert(id: String, baseVersion: Int, fields: [String: AnyCodable]) async {
        let now = clock.now()
        await engine.enqueue(OutboxOp(opId: idGenerator.newID(), entityType: .checklist, entityId: id, op: .upsert,
                                      baseVersion: baseVersion, clientUpdatedAt: now, fields: fields, enqueuedAt: now))
    }
}
