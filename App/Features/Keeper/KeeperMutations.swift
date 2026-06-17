import Foundation
import SwiftData
import SyncCore

/// Local writes + outbox enqueuing for the Keeper feature (notes & folders). Mirrors
/// ``ListMutation``/``TagMutation``: write the `@Model`, mark its sync state, and enqueue a sparse
/// outbox op the ``DefaultSyncEngine`` flushes to `POST /sync/push`.

@MainActor
struct NoteFolderMutation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator
    let ownerId: String

    @discardableResult
    func create(name: String, colorHex: String = "#8E8E93", icon: String = "folder") async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = clock.now()
        let id = idGenerator.newID()
        context.insert(NoteFolderModel(
            id: id, ownerId: ownerId, name: trimmed, colorHex: colorHex, icon: icon,
            sortIndex: 0, createdAt: now, updatedAt: now, serverVersion: 0,
            syncStateRaw: LocalSyncState.pendingCreate.rawValue))
        try? context.save()
        await enqueueUpsert(id: id, baseVersion: 0, fields: [
            "name": .string(trimmed), "colorHex": .string(colorHex), "icon": .string(icon), "sortIndex": .int(0),
        ])
        return id
    }

    func rename(_ folder: NoteFolderModel, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        folder.name = trimmed
        touch(folder)
        await enqueueUpsert(id: folder.id, baseVersion: folder.serverVersion, fields: ["name": .string(trimmed)])
    }

    func setAppearance(_ folder: NoteFolderModel, colorHex: String, icon: String) async {
        folder.colorHex = colorHex
        folder.icon = icon
        touch(folder)
        await enqueueUpsert(id: folder.id, baseVersion: folder.serverVersion,
                            fields: ["colorHex": .string(colorHex), "icon": .string(icon)])
    }

    func delete(_ folder: NoteFolderModel) async {
        let now = clock.now()
        let op = OutboxOp(opId: idGenerator.newID(), entityType: .noteFolder, entityId: folder.id, op: .delete,
                          baseVersion: folder.serverVersion, clientUpdatedAt: now, fields: [:], enqueuedAt: now)
        folder.deletedAt = now
        folder.syncState = .pendingDelete
        try? context.save()
        await engine.enqueue(op)
    }

    private func touch(_ folder: NoteFolderModel) {
        folder.updatedAt = clock.now()
        if folder.syncState == .synced { folder.syncState = .pendingUpdate }
        try? context.save()
    }

    private func enqueueUpsert(id: String, baseVersion: Int, fields: [String: AnyCodable]) async {
        let now = clock.now()
        await engine.enqueue(OutboxOp(opId: idGenerator.newID(), entityType: .noteFolder, entityId: id, op: .upsert,
                                      baseVersion: baseVersion, clientUpdatedAt: now, fields: fields, enqueuedAt: now))
    }
}

@MainActor
struct NoteMutation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator
    let ownerId: String

    @discardableResult
    func create(title: String, folderId: String?, body: String = "") async -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = clock.now()
        let id = idGenerator.newID()
        context.insert(NoteModel(
            id: id, ownerId: ownerId, folderId: folderId, title: trimmed, body: body, pinned: false,
            createdAt: now, updatedAt: now, serverVersion: 0,
            syncStateRaw: LocalSyncState.pendingCreate.rawValue))
        try? context.save()
        await enqueueUpsert(id: id, baseVersion: 0, fields: [
            "title": .string(trimmed),
            "body": .string(body),
            "pinned": .bool(false),
            "folderId": folderId.map { AnyCodable.string($0) } ?? .null,
        ])
        return id
    }

    func setTitle(_ note: NoteModel, _ title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != note.title else { return }
        note.title = trimmed
        touch(note)
        await enqueueUpsert(id: note.id, baseVersion: note.serverVersion, fields: ["title": .string(trimmed)])
    }

    func setBody(_ note: NoteModel, _ body: String) async {
        guard body != note.body else { return }
        note.body = body
        touch(note)
        await enqueueUpsert(id: note.id, baseVersion: note.serverVersion, fields: ["body": .string(body)])
    }

    func setPinned(_ note: NoteModel, _ pinned: Bool) async {
        guard pinned != note.pinned else { return }
        note.pinned = pinned
        touch(note)
        await enqueueUpsert(id: note.id, baseVersion: note.serverVersion, fields: ["pinned": .bool(pinned)])
    }

    func move(_ note: NoteModel, toFolderId folderId: String?) async {
        guard folderId != note.folderId else { return }
        note.folderId = folderId
        touch(note)
        await enqueueUpsert(id: note.id, baseVersion: note.serverVersion,
                            fields: ["folderId": folderId.map { AnyCodable.string($0) } ?? .null])
    }

    /// Link/unlink a note to a task (Keeper task-note linking). Pass nil to unlink.
    func setTaskId(_ note: NoteModel, _ taskId: String?) async {
        guard taskId != note.taskId else { return }
        note.taskId = taskId
        touch(note)
        await enqueueUpsert(id: note.id, baseVersion: note.serverVersion,
                            fields: ["taskId": taskId.map { AnyCodable.string($0) } ?? .null])
    }

    func delete(_ note: NoteModel) async {
        let now = clock.now()
        let op = OutboxOp(opId: idGenerator.newID(), entityType: .note, entityId: note.id, op: .delete,
                          baseVersion: note.serverVersion, clientUpdatedAt: now, fields: [:], enqueuedAt: now)
        note.deletedAt = now
        note.syncState = .pendingDelete
        try? context.save()
        await engine.enqueue(op)
    }

    private func touch(_ note: NoteModel) {
        note.updatedAt = clock.now()
        if note.syncState == .synced { note.syncState = .pendingUpdate }
        try? context.save()
    }

    private func enqueueUpsert(id: String, baseVersion: Int, fields: [String: AnyCodable]) async {
        let now = clock.now()
        await engine.enqueue(OutboxOp(opId: idGenerator.newID(), entityType: .note, entityId: id, op: .upsert,
                                      baseVersion: baseVersion, clientUpdatedAt: now, fields: fields, enqueuedAt: now))
    }
}
