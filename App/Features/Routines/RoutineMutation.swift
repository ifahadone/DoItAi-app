import Foundation
import SwiftData
import SyncCore

/// Create/edit/delete routines + habits, and log a habit completion (DevelopmentPlan P3-4). Writes
/// SwiftData immediately then enqueues a sparse-patch outbox op (steps/recurrence are sent as JSON
/// values). Habit completion goes through ``APIClient/logHabit`` because streak math is server-owned;
/// the returned routine (with the new streak) is applied locally.
@MainActor
struct RoutineMutation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let apiClient: APIClient
    let clock: Clock
    let idGenerator: IDGenerator
    let ownerId: String

    @discardableResult
    func create(
        name: String,
        isHabit: Bool = false,
        steps: [RoutineStep] = [],
        anchorTime: String? = nil,
        recurrence: RoutineRecurrence? = nil,
        chained: Bool = false,
        graceDays: Int = 0,
        colorHex: String = "#4F46E5"
    ) async -> String {
        let now = clock.now()
        let id = idGenerator.newID()
        let model = RoutineModel(
            id: id, ownerId: ownerId, name: name, colorHex: colorHex, anchorTime: anchorTime,
            chained: chained, isHabit: isHabit, graceDays: graceDays,
            createdAt: now, updatedAt: now, serverVersion: 0, syncStateRaw: LocalSyncState.pendingCreate.rawValue
        )
        model.steps = steps
        model.recurrence = recurrence
        context.insert(model)
        try? context.save()
        await enqueue(id: id, baseVersion: 0, fields: fields(
            name: name, colorHex: colorHex, anchorTime: anchorTime, recurrence: recurrence,
            chained: chained, isHabit: isHabit, graceDays: graceDays, steps: steps
        ))
        return id
    }

    func update(
        _ routine: RoutineModel,
        name: String, anchorTime: String?, recurrence: RoutineRecurrence?,
        chained: Bool, graceDays: Int, steps: [RoutineStep]
    ) async {
        let now = clock.now()
        routine.name = name
        routine.anchorTime = anchorTime
        routine.recurrence = recurrence
        routine.chained = chained
        routine.graceDays = graceDays
        routine.steps = steps
        routine.updatedAt = now
        if routine.syncState == .synced { routine.syncState = .pendingUpdate }
        try? context.save()
        await enqueue(id: routine.id, baseVersion: routine.serverVersion, fields: fields(
            name: name, colorHex: routine.colorHex, anchorTime: anchorTime, recurrence: recurrence,
            chained: chained, isHabit: routine.isHabit, graceDays: graceDays, steps: steps
        ))
    }

    /// Duplicate a routine/habit as a new "… copy" with the same steps, schedule, and settings — a
    /// fresh entity via the normal create path (so it syncs as a create, not a clone of the original).
    @discardableResult
    func duplicate(_ routine: RoutineModel) async -> String {
        await create(
            name: routine.name.isEmpty ? "Routine copy" : "\(routine.name) copy",
            isHabit: routine.isHabit, steps: routine.steps, anchorTime: routine.anchorTime,
            recurrence: routine.recurrence, chained: routine.chained, graceDays: routine.graceDays,
            colorHex: routine.colorHex
        )
    }

    func delete(_ routine: RoutineModel) async {
        let now = clock.now()
        let op = OutboxOp(opId: idGenerator.newID(), entityType: .routine, entityId: routine.id, op: .delete,
                          baseVersion: routine.serverVersion, clientUpdatedAt: now, fields: [:], enqueuedAt: now)
        routine.deletedAt = now
        routine.syncState = .pendingDelete
        try? context.save()
        await engine.enqueue(op)
    }

    /// Log today's completion for a habit; the server returns the updated routine (new streak).
    @discardableResult
    func logHabitToday(_ routine: RoutineModel) async -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: clock.now())
        guard let dto = try? await apiClient.logHabit(routineId: routine.id, date: today) else { return false }
        routine.apply(dto)
        try? context.save()
        return true
    }

    // MARK: - Field encoding

    private func enqueue(id: String, baseVersion: Int, fields: [String: AnyCodable]) async {
        let now = clock.now()
        await engine.enqueue(OutboxOp(opId: idGenerator.newID(), entityType: .routine, entityId: id, op: .upsert,
                                      baseVersion: baseVersion, clientUpdatedAt: now, fields: fields, enqueuedAt: now))
    }

    private func fields(
        name: String, colorHex: String, anchorTime: String?, recurrence: RoutineRecurrence?,
        chained: Bool, isHabit: Bool, graceDays: Int, steps: [RoutineStep]
    ) -> [String: AnyCodable] {
        [
            "name": .string(name),
            "colorHex": .string(colorHex),
            "anchorTime": anchorTime.map(AnyCodable.string) ?? .null,
            "recurrence": recurrenceField(recurrence),
            "chained": .bool(chained),
            "isHabit": .bool(isHabit),
            "graceDays": .int(graceDays),
            "steps": .array(steps.map { step in
                .object(["title": .string(step.title), "minutes": .int(step.minutes),
                         "ord": .int(step.ord), "hasAlarm": .bool(step.hasAlarm)])
            }),
        ]
    }

    private func recurrenceField(_ recurrence: RoutineRecurrence?) -> AnyCodable {
        guard let recurrence else { return .null }
        var object: [String: AnyCodable] = [:]
        if let weekdays = recurrence.weekdays { object["weekdays"] = .array(weekdays.map(AnyCodable.int)) }
        if let everyNDays = recurrence.everyNDays { object["everyNDays"] = .int(everyNDays) }
        return .object(object)
    }
}
