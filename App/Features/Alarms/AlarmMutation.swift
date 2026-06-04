import Foundation
import SwiftData
import SyncCore

/// Create/delete alarm records (AppSpec §5.6, DevelopmentPlan P3-6). Alarms sync like any entity; the
/// CLIENT owns delivery (see ``AlarmScheduler`` + the iOS reality caveat). Used directly and by the
/// routine "alarm chain" (one alarm per `hasAlarm` step at its start time).
@MainActor
struct AlarmMutation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator
    let ownerId: String

    @discardableResult
    func create(
        taskId: String? = nil,
        fireAt: Date?,
        type: Int = 0,
        soundName: String? = nil,
        snoozeMinutes: Int? = nil,
        usesLiveActivity: Bool = false
    ) async -> String {
        let now = clock.now()
        let id = idGenerator.newID()
        context.insert(AlarmModel(
            id: id, ownerId: ownerId, taskId: taskId, fireAt: fireAt, type: type,
            soundName: soundName, snoozeMinutes: snoozeMinutes, usesLiveActivity: usesLiveActivity,
            createdAt: now, updatedAt: now, serverVersion: 0, syncStateRaw: LocalSyncState.pendingCreate.rawValue
        ))
        try? context.save()
        await engine.enqueue(OutboxOp(
            opId: idGenerator.newID(), entityType: .alarm, entityId: id, op: .upsert,
            baseVersion: 0, clientUpdatedAt: now,
            fields: [
                "taskId": taskId.map(AnyCodable.string) ?? .null,
                "fireAt": fireAt.map { AnyCodable.string(TaskMutation.iso($0)) } ?? .null,
                "type": .int(type),
                "soundName": soundName.map(AnyCodable.string) ?? .null,
                "snoozeMinutes": snoozeMinutes.map(AnyCodable.int) ?? .null,
                "usesLiveActivity": .bool(usesLiveActivity),
            ],
            enqueuedAt: now
        ))
        return id
    }

    func delete(_ alarm: AlarmModel) async {
        let now = clock.now()
        let op = OutboxOp(opId: idGenerator.newID(), entityType: .alarm, entityId: alarm.id, op: .delete,
                          baseVersion: alarm.serverVersion, clientUpdatedAt: now, fields: [:], enqueuedAt: now)
        alarm.deletedAt = now
        alarm.syncState = .pendingDelete
        try? context.save()
        await engine.enqueue(op)
    }
}
