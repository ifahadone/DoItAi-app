import Foundation
import SwiftData
import SyncCore

/// Create/delete reminders (AppSpec §5.7, P3-7 location reminders). Reminders sync like any entity; the
/// CLIENT owns delivery — time-based via ``NotificationScheduler``, location via ``LocationReminderService``.
@MainActor
struct ReminderMutation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator
    let ownerId: String

    /// An absolute-time (kind 0) reminder for a task.
    @discardableResult
    func createAbsolute(taskId: String, fireAt: Date, interruption: Int = 1) async -> String {
        let now = clock.now()
        let id = idGenerator.newID()
        context.insert(ReminderModel(
            id: id, ownerId: ownerId, taskId: taskId, kind: 0, fireAt: fireAt, interruption: interruption,
            createdAt: now, updatedAt: now, serverVersion: 0, syncStateRaw: LocalSyncState.pendingCreate.rawValue
        ))
        try? context.save()
        await engine.enqueue(OutboxOp(
            opId: idGenerator.newID(), entityType: .reminder, entityId: id, op: .upsert,
            baseVersion: 0, clientUpdatedAt: now,
            fields: [
                "taskId": .string(taskId),
                "kind": .int(0),
                "fireAt": .string(TaskMutation.iso(fireAt)),
                "interruption": .int(interruption),
            ],
            enqueuedAt: now
        ))
        return id
    }

    /// A geofenced (kind 2) reminder for a task.
    @discardableResult
    func createLocation(taskId: String, region: ReminderRegion, interruption: Int = 1) async -> String {
        let now = clock.now()
        let id = idGenerator.newID()
        let model = ReminderModel(
            id: id, ownerId: ownerId, taskId: taskId, kind: 2, interruption: interruption,
            createdAt: now, updatedAt: now, serverVersion: 0,
            syncStateRaw: LocalSyncState.pendingCreate.rawValue
        )
        model.region = region
        context.insert(model)
        try? context.save()
        await engine.enqueue(OutboxOp(
            opId: idGenerator.newID(), entityType: .reminder, entityId: id, op: .upsert,
            baseVersion: 0, clientUpdatedAt: now,
            fields: [
                "taskId": .string(taskId),
                "kind": .int(2),
                "interruption": .int(interruption),
                "region": Self.regionField(region),
            ],
            enqueuedAt: now
        ))
        return id
    }

    func delete(_ reminder: ReminderModel) async {
        let now = clock.now()
        let op = OutboxOp(opId: idGenerator.newID(), entityType: .reminder, entityId: reminder.id, op: .delete,
                          baseVersion: reminder.serverVersion, clientUpdatedAt: now, fields: [:], enqueuedAt: now)
        reminder.deletedAt = now
        reminder.syncState = .pendingDelete
        try? context.save()
        await engine.enqueue(op)
    }

    /// Encode a region as the server's JSON shape (`{ center: { lat, lon, name? }, radius, onEntry, onExit }`).
    static func regionField(_ region: ReminderRegion) -> AnyCodable {
        var center: [String: AnyCodable] = ["lat": .double(region.center.lat), "lon": .double(region.center.lon)]
        if let name = region.center.name { center["name"] = .string(name) }
        return .object([
            "center": .object(center),
            "radius": .double(region.radius),
            "onEntry": .bool(region.onEntry),
            "onExit": .bool(region.onExit),
        ])
    }
}
