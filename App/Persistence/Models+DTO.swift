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
}
