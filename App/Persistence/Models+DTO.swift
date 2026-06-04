import Foundation
import SyncCore

// Typed accessors over the raw-Int columns, plus DTO <-> @Model conversion. Keeping conversion here
// (rather than in SyncCore) preserves the layering rule: SyncCore is framework-free and knows
// nothing about SwiftData; the app target owns the mapping between persistence and the wire shape.

// MARK: - TaskModel typed accessors + conversion

extension TaskModel {
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var energy: Energy? {
        get { energyRaw.flatMap(Energy.init(rawValue:)) }
        set { energyRaw = newValue?.rawValue }
    }

    var syncState: LocalSyncState {
        get { LocalSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    var recurrence: RecurrenceRule? {
        get { recurrenceData.flatMap { try? JSONCoding.makeDecoder().decode(RecurrenceRule.self, from: $0) } }
        set { recurrenceData = newValue.flatMap { try? JSONCoding.makeEncoder().encode($0) } }
    }

    var location: GeoPoint? {
        get { locationData.flatMap { try? JSONCoding.makeDecoder().decode(GeoPoint.self, from: $0) } }
        set { locationData = newValue.flatMap { try? JSONCoding.makeEncoder().encode($0) } }
    }

    /// Project this persisted row into the wire DTO (for push / debugging).
    func toDTO() -> TaskDTO {
        TaskDTO(
            id: id,
            ownerId: ownerId,
            listId: listId,
            parentTaskId: parentTaskId,
            title: title,
            notes: notes,
            status: status,
            priority: priority,
            rank: rank,
            energy: energy,
            dueAt: dueAt,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
            estimatedMinutes: estimatedMinutes,
            actualMinutes: actualMinutes,
            isAllDay: isAllDay,
            recurrence: recurrence,
            recurrenceParentId: recurrenceParentId,
            routineInstanceOf: routineInstanceOf,
            assigneeUserId: assigneeUserId,
            location: location,
            url: url,
            tagIds: tagIds,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt,
            archived: archived,
            serverVersion: serverVersion,
            deletedAt: deletedAt
        )
    }

    /// Build a fresh model from a pulled DTO.
    static func make(from dto: TaskDTO) -> TaskModel {
        let model = TaskModel(
            id: dto.id,
            ownerId: dto.ownerId,
            title: dto.title,
            statusRaw: dto.status.rawValue,
            priorityRaw: dto.priority.rawValue,
            rank: dto.rank,
            isAllDay: dto.isAllDay,
            tagIds: dto.tagIds,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            archived: dto.archived,
            serverVersion: dto.serverVersion,
            syncStateRaw: LocalSyncState.synced.rawValue
        )
        model.apply(dto)
        return model
    }

    /// Overwrite local fields from an authoritative pulled DTO (last-writer-wins is resolved
    /// server-side; the client trusts the pulled snapshot — AppSpec §8).
    func apply(_ dto: TaskDTO) {
        ownerId = dto.ownerId
        listId = dto.listId
        parentTaskId = dto.parentTaskId
        title = dto.title
        notes = dto.notes
        status = dto.status
        priority = dto.priority
        rank = dto.rank
        energy = dto.energy
        dueAt = dto.dueAt
        scheduledStart = dto.scheduledStart
        scheduledEnd = dto.scheduledEnd
        estimatedMinutes = dto.estimatedMinutes
        actualMinutes = dto.actualMinutes
        isAllDay = dto.isAllDay
        recurrence = dto.recurrence
        recurrenceParentId = dto.recurrenceParentId
        routineInstanceOf = dto.routineInstanceOf
        assigneeUserId = dto.assigneeUserId
        location = dto.location
        url = dto.url
        tagIds = dto.tagIds
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        completedAt = dto.completedAt
        archived = dto.archived
        serverVersion = dto.serverVersion
        deletedAt = dto.deletedAt
        syncState = .synced
    }
}

// MARK: - TaskListModel

extension TaskListModel {
    var syncState: LocalSyncState {
        get { LocalSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    func toDTO() -> TaskListDTO {
        TaskListDTO(
            id: id, ownerId: ownerId, name: name, colorHex: colorHex, icon: icon,
            sortIndex: sortIndex, shareId: shareId, createdAt: createdAt, updatedAt: updatedAt,
            serverVersion: serverVersion, deletedAt: deletedAt
        )
    }

    /// Build a fresh list model from a pulled DTO.
    static func make(from dto: TaskListDTO) -> TaskListModel {
        let model = TaskListModel(
            id: dto.id, ownerId: dto.ownerId, name: dto.name, colorHex: dto.colorHex,
            icon: dto.icon, sortIndex: dto.sortIndex, createdAt: dto.createdAt, updatedAt: dto.updatedAt,
            serverVersion: dto.serverVersion, syncStateRaw: LocalSyncState.synced.rawValue
        )
        model.apply(dto)
        return model
    }

    /// Overwrite local fields from an authoritative pulled DTO.
    func apply(_ dto: TaskListDTO) {
        ownerId = dto.ownerId
        name = dto.name
        colorHex = dto.colorHex
        icon = dto.icon
        sortIndex = dto.sortIndex
        shareId = dto.shareId
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        serverVersion = dto.serverVersion
        deletedAt = dto.deletedAt
        syncState = .synced
    }
}

// MARK: - TagModel

extension TagModel {
    var syncState: LocalSyncState {
        get { LocalSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    func toDTO() -> TagDTO {
        TagDTO(
            id: id, ownerId: ownerId, name: name, colorHex: colorHex,
            createdAt: createdAt, updatedAt: updatedAt, serverVersion: serverVersion, deletedAt: deletedAt
        )
    }

    /// Build a fresh tag model from a pulled DTO.
    static func make(from dto: TagDTO) -> TagModel {
        let model = TagModel(
            id: dto.id, ownerId: dto.ownerId, name: dto.name, colorHex: dto.colorHex,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt,
            serverVersion: dto.serverVersion, syncStateRaw: LocalSyncState.synced.rawValue
        )
        model.apply(dto)
        return model
    }

    /// Overwrite local fields from an authoritative pulled DTO.
    func apply(_ dto: TagDTO) {
        ownerId = dto.ownerId
        name = dto.name
        colorHex = dto.colorHex
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        serverVersion = dto.serverVersion
        deletedAt = dto.deletedAt
        syncState = .synced
    }
}

// MARK: - ReminderModel

extension ReminderModel {
    var syncState: LocalSyncState {
        get { LocalSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    func toDTO() -> ReminderDTO {
        ReminderDTO(
            id: id, ownerId: ownerId, taskId: taskId, kind: kind, fireAt: fireAt,
            offsetMinutes: offsetMinutes, interruption: interruption, notificationId: notificationId,
            createdAt: createdAt, updatedAt: updatedAt, serverVersion: serverVersion, deletedAt: deletedAt
        )
    }

    static func make(from dto: ReminderDTO) -> ReminderModel {
        let model = ReminderModel(
            id: dto.id, ownerId: dto.ownerId, taskId: dto.taskId, kind: dto.kind, fireAt: dto.fireAt,
            offsetMinutes: dto.offsetMinutes, interruption: dto.interruption, notificationId: dto.notificationId,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt, serverVersion: dto.serverVersion,
            syncStateRaw: LocalSyncState.synced.rawValue
        )
        model.apply(dto)
        return model
    }

    func apply(_ dto: ReminderDTO) {
        ownerId = dto.ownerId
        taskId = dto.taskId
        kind = dto.kind
        fireAt = dto.fireAt
        offsetMinutes = dto.offsetMinutes
        interruption = dto.interruption
        notificationId = dto.notificationId
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        serverVersion = dto.serverVersion
        deletedAt = dto.deletedAt
        syncState = .synced
    }
}

// MARK: - ChecklistItemModel

extension ChecklistItemModel {
    var syncState: LocalSyncState {
        get { LocalSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    func toDTO() -> ChecklistItemDTO {
        ChecklistItemDTO(
            id: id, ownerId: ownerId, taskId: taskId, text: text, done: done, ord: ord,
            createdAt: createdAt, updatedAt: updatedAt, serverVersion: serverVersion, deletedAt: deletedAt
        )
    }

    static func make(from dto: ChecklistItemDTO) -> ChecklistItemModel {
        let model = ChecklistItemModel(
            id: dto.id, ownerId: dto.ownerId, taskId: dto.taskId, text: dto.text, done: dto.done, ord: dto.ord,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt, serverVersion: dto.serverVersion,
            syncStateRaw: LocalSyncState.synced.rawValue
        )
        model.apply(dto)
        return model
    }

    func apply(_ dto: ChecklistItemDTO) {
        ownerId = dto.ownerId
        taskId = dto.taskId
        text = dto.text
        done = dto.done
        ord = dto.ord
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        serverVersion = dto.serverVersion
        deletedAt = dto.deletedAt
        syncState = .synced
    }
}

// MARK: - RoutineModel

extension RoutineModel {
    var syncState: LocalSyncState {
        get { LocalSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    var steps: [RoutineStep] {
        get { stepsData.flatMap { try? JSONCoding.makeDecoder().decode([RoutineStep].self, from: $0) } ?? [] }
        set { stepsData = try? JSONCoding.makeEncoder().encode(newValue) }
    }

    var recurrence: RoutineRecurrence? {
        get { recurrenceData.flatMap { try? JSONCoding.makeDecoder().decode(RoutineRecurrence.self, from: $0) } }
        set { recurrenceData = newValue.flatMap { try? JSONCoding.makeEncoder().encode($0) } }
    }

    func toDTO() -> RoutineDTO {
        RoutineDTO(
            id: id, ownerId: ownerId, name: name, colorHex: colorHex, anchorTime: anchorTime,
            recurrence: recurrence, chained: chained, isHabit: isHabit, streakCurrent: streakCurrent,
            streakLongest: streakLongest, graceDays: graceDays, steps: steps,
            createdAt: createdAt, updatedAt: updatedAt, serverVersion: serverVersion, deletedAt: deletedAt
        )
    }

    static func make(from dto: RoutineDTO) -> RoutineModel {
        let model = RoutineModel(
            id: dto.id, ownerId: dto.ownerId, name: dto.name, colorHex: dto.colorHex,
            anchorTime: dto.anchorTime, chained: dto.chained, isHabit: dto.isHabit,
            streakCurrent: dto.streakCurrent, streakLongest: dto.streakLongest, graceDays: dto.graceDays,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt, serverVersion: dto.serverVersion,
            syncStateRaw: LocalSyncState.synced.rawValue
        )
        model.apply(dto)
        return model
    }

    func apply(_ dto: RoutineDTO) {
        ownerId = dto.ownerId
        name = dto.name
        colorHex = dto.colorHex
        anchorTime = dto.anchorTime
        recurrence = dto.recurrence
        chained = dto.chained
        isHabit = dto.isHabit
        streakCurrent = dto.streakCurrent
        streakLongest = dto.streakLongest
        graceDays = dto.graceDays
        steps = dto.steps
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        serverVersion = dto.serverVersion
        deletedAt = dto.deletedAt
        syncState = .synced
    }
}

// MARK: - AlarmModel

extension AlarmModel {
    var syncState: LocalSyncState {
        get { LocalSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    func toDTO() -> AlarmDTO {
        AlarmDTO(
            id: id, ownerId: ownerId, taskId: taskId, fireAt: fireAt, type: type,
            soundName: soundName, snoozeMinutes: snoozeMinutes, usesLiveActivity: usesLiveActivity,
            createdAt: createdAt, updatedAt: updatedAt, serverVersion: serverVersion, deletedAt: deletedAt
        )
    }

    static func make(from dto: AlarmDTO) -> AlarmModel {
        let model = AlarmModel(
            id: dto.id, ownerId: dto.ownerId, taskId: dto.taskId, fireAt: dto.fireAt, type: dto.type,
            soundName: dto.soundName, snoozeMinutes: dto.snoozeMinutes, usesLiveActivity: dto.usesLiveActivity,
            createdAt: dto.createdAt, updatedAt: dto.updatedAt, serverVersion: dto.serverVersion,
            syncStateRaw: LocalSyncState.synced.rawValue
        )
        model.apply(dto)
        return model
    }

    func apply(_ dto: AlarmDTO) {
        ownerId = dto.ownerId
        taskId = dto.taskId
        fireAt = dto.fireAt
        type = dto.type
        soundName = dto.soundName
        snoozeMinutes = dto.snoozeMinutes
        usesLiveActivity = dto.usesLiveActivity
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        serverVersion = dto.serverVersion
        deletedAt = dto.deletedAt
        syncState = .synced
    }
}
