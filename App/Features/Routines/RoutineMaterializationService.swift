import Foundation
import SwiftData
import SyncCore

/// Materializes routines into the day's plan (AppSpec §5.2 "Generation", DevelopmentPlan P3-3). For
/// each non-habit routine that occurs today (per ``SyncCore/RoutineMaterializer``), it creates one
/// scheduled Task per step (tagged `routineInstanceOf`) — which then appears on the dial + planner.
/// Idempotent: a routine that already has instances scheduled today is skipped, so it's safe to run on
/// every launch / from BGTaskScheduler.
@MainActor
struct RoutineMaterializationService {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator
    let ownerId: String

    @discardableResult
    func materializeToday() async -> Int {
        let now = clock.now()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)

        let routines = (try? context.fetch(FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let scheduled = (try? context.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []

        var ops: [OutboxOp] = []
        for routine in routines where !routine.isHabit {
            guard RoutineMaterializer.occurs(recurrence: routine.recurrence, on: now, calendar: calendar) else { continue }
            let alreadyToday = scheduled.contains { task in
                task.routineInstanceOf == routine.id
                    && (task.scheduledStart.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
            }
            if alreadyToday { continue }

            for instance in RoutineMaterializer.instances(steps: routine.steps, anchorTime: routine.anchorTime) {
                guard let start = calendar.date(byAdding: .minute, value: instance.startMinute, to: startOfDay),
                      let end = calendar.date(byAdding: .minute, value: instance.endMinute, to: startOfDay) else { continue }
                ops.append(makeInstance(title: instance.title, start: start, end: end, routineId: routine.id, now: now))
            }
        }

        try? context.save()
        for op in ops { await engine.enqueue(op) }
        return ops.count
    }

    private func makeInstance(title: String, start: Date, end: Date, routineId: String, now: Date) -> OutboxOp {
        let id = idGenerator.newID()
        let model = TaskModel(
            id: id, ownerId: ownerId, title: title, statusRaw: TaskStatus.scheduled.rawValue,
            createdAt: now, updatedAt: now, serverVersion: 0, syncStateRaw: LocalSyncState.pendingCreate.rawValue
        )
        model.scheduledStart = start
        model.scheduledEnd = end
        model.routineInstanceOf = routineId
        context.insert(model)

        return OutboxOp(
            opId: idGenerator.newID(), entityType: .task, entityId: id, op: .upsert,
            baseVersion: 0, clientUpdatedAt: now,
            fields: [
                "title": .string(title),
                "status": .int(TaskStatus.scheduled.rawValue),
                "rank": .int(0),
                "isAllDay": .bool(false),
                "scheduledStart": .string(TaskMutation.iso(start)),
                "scheduledEnd": .string(TaskMutation.iso(end)),
                "routineInstanceOf": .string(routineId),
            ],
            enqueuedAt: now
        )
    }
}
