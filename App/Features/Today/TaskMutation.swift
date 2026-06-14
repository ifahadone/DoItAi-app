import Foundation
import SwiftData
import SyncCore

/// Mutates existing tasks locally and enqueues sparse-patch outbox ops (AppSpec §8, DevelopmentPlan
/// P1-E). Companion to ``TaskCreation`` (creates). Every method writes SwiftData immediately
/// (offline-first) then enqueues an op carrying ONLY the changed, writable columns — `baseVersion` is
/// the task's last-seen `serverVersion` so the server's field-level LWW resolves concurrent edits
/// (ApiSpec §6.1, P1-A). Time/ids come from injected ``Clock``/``IDGenerator`` (AppSpec §16).
@MainActor
struct TaskMutation {
    let context: ModelContext
    let engine: DefaultSyncEngine
    let clock: Clock
    let idGenerator: IDGenerator

    // MARK: - Field edits

    /// Toggle done ⇄ inbox, stamping/clearing `completedAt`. Completing a recurring task spawns its
    /// next instance (client-side materialization; the server never expands recurrences).
    func toggleComplete(_ task: TaskModel) async {
        let done = task.status != .done
        let when = clock.now()
        await patch(task, fields: [
            "status": .int((done ? TaskStatus.done : TaskStatus.inbox).rawValue),
            "completedAt": done ? .string(Self.iso(when)) : .null,
        ]) { t in
            t.status = done ? .done : .inbox
            t.completedAt = done ? when : nil
        }
        if done { await spawnNextRecurrence(of: task, completedAt: when) }
    }

    /// Set/clear the task's recurrence rule (RFC-5545 subset; synced as a JSON object).
    func setRecurrence(_ task: TaskModel, _ rule: RecurrenceRule?) async {
        guard rule != task.recurrence else { return }
        await patch(task, fields: ["recurrence": rule.map(Self.recurrenceField) ?? .null]) { $0.recurrence = rule }
    }

    /// Encode a ``RecurrenceRule`` into the wire object the server's RecurrenceRuleSchema accepts.
    static func recurrenceField(_ rule: RecurrenceRule) -> AnyCodable {
        var obj: [String: AnyCodable] = ["freq": .string(rule.freq.rawValue), "interval": .int(rule.interval)]
        if let until = rule.until { obj["until"] = .string(iso(until)) }
        return .object(obj)
    }

    /// On completing a recurring task, create the next instance (next due date from the rule), copying
    /// the carry-over fields and linking it to the series via `recurrenceParentId`.
    private func spawnNextRecurrence(of task: TaskModel, completedAt: Date) async {
        guard let rule = task.recurrence else { return }
        let anchor = task.dueAt ?? task.scheduledStart ?? completedAt
        guard let next = RecurrenceEngine.nextOccurrence(after: anchor, rule: rule) else { return }
        let now = clock.now()
        let id = idGenerator.newID()
        let clone = TaskModel(
            id: id, ownerId: task.ownerId, title: task.title,
            statusRaw: TaskStatus.inbox.rawValue, priorityRaw: task.priorityRaw,
            createdAt: now, updatedAt: now, serverVersion: 0,
            syncStateRaw: LocalSyncState.pendingCreate.rawValue)
        clone.dueAt = next
        clone.listId = task.listId
        clone.notes = task.notes
        clone.energyRaw = task.energyRaw
        clone.tagIds = task.tagIds
        clone.recurrence = rule
        clone.recurrenceParentId = task.recurrenceParentId ?? task.id
        context.insert(clone)
        try? context.save()

        var fields: [String: AnyCodable] = [
            "title": .string(task.title),
            "status": .int(TaskStatus.inbox.rawValue),
            "dueAt": .string(Self.iso(next)),
            "priority": .int(task.priorityRaw),
            "recurrence": Self.recurrenceField(rule),
            "recurrenceParentId": .string(task.recurrenceParentId ?? task.id),
        ]
        if let listId = task.listId { fields["listId"] = .string(listId) }
        if !task.tagIds.isEmpty { fields["tagIds"] = .array(task.tagIds.map(AnyCodable.string)) }
        if let energy = task.energyRaw { fields["energy"] = .int(energy) }
        if let notes = task.notes, !notes.isEmpty { fields["notes"] = .string(notes) }
        await engine.enqueue(OutboxOp(opId: idGenerator.newID(), entityType: .task, entityId: id, op: .upsert,
                                      baseVersion: 0, clientUpdatedAt: now, fields: fields, enqueuedAt: now))
    }

    func setTitle(_ task: TaskModel, _ title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        await patch(task, fields: ["title": .string(trimmed)]) { $0.title = trimmed }
    }

    func setNotes(_ task: TaskModel, _ notes: String?) async {
        let value = (notes?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        guard value != task.notes else { return }
        await patch(task, fields: ["notes": value.map(AnyCodable.string) ?? .null]) { $0.notes = value }
    }

    func setPriority(_ task: TaskModel, _ priority: Priority) async {
        guard priority != task.priority else { return }
        await patch(task, fields: ["priority": .int(priority.rawValue)]) { $0.priority = priority }
    }

    /// Set/clear the task's energy level (already synced, previously had no UI).
    func setEnergy(_ task: TaskModel, _ energy: Energy?) async {
        guard energy != task.energy else { return }
        await patch(task, fields: ["energy": energy.map { AnyCodable.int($0.rawValue) } ?? .null]) { $0.energy = energy }
    }

    func reschedule(_ task: TaskModel, dueAt: Date?) async {
        guard dueAt != task.dueAt else { return }
        await patch(task, fields: ["dueAt": dueAt.map { AnyCodable.string(Self.iso($0)) } ?? .null]) { $0.dueAt = dueAt }
    }

    /// Add focus-timer minutes to the task's logged `actualMinutes` (P2-4).
    func addActualMinutes(_ task: TaskModel, _ minutes: Int) async {
        guard minutes > 0 else { return }
        let total = (task.actualMinutes ?? 0) + minutes
        await patch(task, fields: ["actualMinutes": .int(total)]) { $0.actualMinutes = total }
    }

    /// Place/move/resize a task's time block on the planner + dial (P2).
    func setSchedule(_ task: TaskModel, start: Date?, end: Date?) async {
        guard start != task.scheduledStart || end != task.scheduledEnd else { return }
        await patch(task, fields: [
            "scheduledStart": start.map { AnyCodable.string(Self.iso($0)) } ?? .null,
            "scheduledEnd": end.map { AnyCodable.string(Self.iso($0)) } ?? .null,
        ]) { t in
            t.scheduledStart = start
            t.scheduledEnd = end
        }
    }

    func assign(_ task: TaskModel, toListId listId: String?) async {
        guard listId != task.listId else { return }
        await patch(task, fields: ["listId": listId.map(AnyCodable.string) ?? .null]) { $0.listId = listId }
    }

    /// Replace the task's tags (the server resolves `tagIds` into the task_tags join table).
    func setTags(_ task: TaskModel, tagIds: [String]) async {
        guard tagIds != task.tagIds else { return }
        await patch(task, fields: ["tagIds": .array(tagIds.map(AnyCodable.string))]) { $0.tagIds = tagIds }
    }

    // MARK: - Delete

    /// Soft-delete locally (the Today query hides `deletedAt != nil`) + enqueue a delete tombstone.
    func delete(_ task: TaskModel) async {
        let now = clock.now()
        // Delete carries no patch; OutboxOp.fields is non-optional so use an empty bag (the wire sends
        // `{}`, which the server ignores for deletes).
        let op = OutboxOp(
            opId: idGenerator.newID(), entityType: .task, entityId: task.id, op: .delete,
            baseVersion: task.serverVersion, clientUpdatedAt: now, fields: [:], enqueuedAt: now
        )
        task.deletedAt = now
        task.syncState = .pendingDelete
        try? context.save()
        await engine.enqueue(op)
    }

    // MARK: - Core

    /// Apply a local mutation + enqueue a sparse upsert patch (only the changed writable columns).
    private func patch(_ task: TaskModel, fields: [String: AnyCodable], _ mutate: (TaskModel) -> Void) async {
        let now = clock.now()
        mutate(task)
        task.updatedAt = now
        if task.syncState == .synced { task.syncState = .pendingUpdate }
        try? context.save()
        let op = OutboxOp(
            opId: idGenerator.newID(), entityType: .task, entityId: task.id, op: .upsert,
            baseVersion: task.serverVersion, clientUpdatedAt: now, fields: fields, enqueuedAt: now
        )
        await engine.enqueue(op)
    }

    /// RFC 3339 (no fractional seconds) for embedding dates in the patch field bag.
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
