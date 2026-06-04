import Foundation
import SwiftData
import SyncCore

// SwiftData `@Model` types — the local source of truth (AppSpec §6, §7). Each model mirrors its
// SyncCore DTO field-for-field so converting between the persisted row and the wire shape is
// mechanical. Integer-backed enums are stored as their `rawValue` `Int` (SwiftData persists the raw
// scalar), keeping parity with the server SMALLINT columns.
//
// NOTE: This file requires the Xcode **app target** (SwiftData isn't available to the pure SPM
// packages). It will not compile via `swift build` on its own — that's expected for Phase 0.
//
// Phase 0 models a thin slice: Task, TaskList, Tag — enough for the walking skeleton (sign in →
// create offline → sync → pull). Routines/Reminders/Alarms/Shares/etc. arrive in later phases.

// MARK: - Task

@Model
final class TaskModel {
    /// Client-generated UUID string; stable across offline→sync (AppSpec §6).
    @Attribute(.unique) var id: String
    var ownerId: String
    var listId: String?
    var parentTaskId: String?

    var title: String
    var notes: String?
    /// Stored as `TaskStatus.rawValue`. Use ``status`` for the typed accessor.
    var statusRaw: Int
    /// Stored as `Priority.rawValue`.
    var priorityRaw: Int
    var rank: Int
    /// Stored as `Energy.rawValue`; nil when unset.
    var energyRaw: Int?

    // Scheduling
    var dueAt: Date?
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var estimatedMinutes: Int?
    var actualMinutes: Int?
    var isAllDay: Bool

    // Recurrence / routine linkage. `recurrence` is stored as encoded JSON `Data` to keep the @Model
    // free of nested Codable structs; convert via SyncCore's RecurrenceRule.
    var recurrenceData: Data?
    var recurrenceParentId: String?
    var routineInstanceOf: String?

    // Relationships / collaboration. tagIds is the flattened M:N (server task_tags). A real
    // @Relationship to TagModel is deferred to Phase 1 to keep the Phase 0 schema minimal.
    var assigneeUserId: String?
    var locationData: Data?     // encoded GeoPoint
    var url: String?
    var tagIds: [String]

    // Audit / sync
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var archived: Bool
    /// Server version for conflict detection (AppSpec §8). 0 until first synced.
    var serverVersion: Int
    /// Soft-delete tombstone (AppSpec §6 / ApiSpec §5).
    var deletedAt: Date?
    /// Local sync state for the outbox (AppSpec §6 `SyncState`). Stored as raw `Int`.
    var syncStateRaw: Int

    init(
        id: String,
        ownerId: String,
        title: String,
        statusRaw: Int = TaskStatus.inbox.rawValue,
        priorityRaw: Int = Priority.none.rawValue,
        rank: Int = 0,
        isAllDay: Bool = false,
        tagIds: [String] = [],
        createdAt: Date,
        updatedAt: Date,
        archived: Bool = false,
        serverVersion: Int = 0,
        syncStateRaw: Int = LocalSyncState.pendingCreate.rawValue
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.statusRaw = statusRaw
        self.priorityRaw = priorityRaw
        self.rank = rank
        self.isAllDay = isAllDay
        self.tagIds = tagIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archived = archived
        self.serverVersion = serverVersion
        self.syncStateRaw = syncStateRaw
    }
}

// MARK: - TaskList

@Model
final class TaskListModel {
    @Attribute(.unique) var id: String
    var ownerId: String
    var name: String
    var colorHex: String
    /// SF Symbol name.
    var icon: String
    var sortIndex: Int
    var shareId: String?

    var createdAt: Date
    var updatedAt: Date
    var serverVersion: Int
    var deletedAt: Date?
    var syncStateRaw: Int

    init(
        id: String,
        ownerId: String,
        name: String,
        colorHex: String,
        icon: String,
        sortIndex: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        syncStateRaw: Int = LocalSyncState.pendingCreate.rawValue
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.syncStateRaw = syncStateRaw
    }
}

// MARK: - Tag

@Model
final class TagModel {
    @Attribute(.unique) var id: String
    var ownerId: String
    var name: String
    var colorHex: String

    var createdAt: Date
    var updatedAt: Date
    var serverVersion: Int
    var deletedAt: Date?
    var syncStateRaw: Int

    init(
        id: String,
        ownerId: String,
        name: String,
        colorHex: String,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        syncStateRaw: Int = LocalSyncState.pendingCreate.rawValue
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.syncStateRaw = syncStateRaw
    }
}

// MARK: - Reminder

@Model
final class ReminderModel {
    @Attribute(.unique) var id: String
    var ownerId: String
    var taskId: String
    /// 0 absolute · 1 relativeToDue · 2 location · 3 recurring.
    var kind: Int
    var fireAt: Date?
    var offsetMinutes: Int?
    /// 0 passive · 1 active · 2 timeSensitive · 3 critical.
    var interruption: Int
    /// The scheduled `UNNotificationRequest` id (set by the local scheduler), if any.
    var notificationId: String?
    /// JSON-encoded ``SyncCore/ReminderRegion`` for a location reminder (kind 2); nil otherwise.
    var regionData: Data?

    var createdAt: Date
    var updatedAt: Date
    var serverVersion: Int
    var deletedAt: Date?
    var syncStateRaw: Int

    init(
        id: String,
        ownerId: String,
        taskId: String,
        kind: Int = 0,
        fireAt: Date? = nil,
        offsetMinutes: Int? = nil,
        interruption: Int = 1,
        notificationId: String? = nil,
        regionData: Data? = nil,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        syncStateRaw: Int = LocalSyncState.pendingCreate.rawValue
    ) {
        self.id = id
        self.ownerId = ownerId
        self.taskId = taskId
        self.kind = kind
        self.fireAt = fireAt
        self.offsetMinutes = offsetMinutes
        self.interruption = interruption
        self.notificationId = notificationId
        self.regionData = regionData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.syncStateRaw = syncStateRaw
    }
}

// MARK: - ChecklistItem

@Model
final class ChecklistItemModel {
    @Attribute(.unique) var id: String
    var ownerId: String
    var taskId: String
    var text: String
    var done: Bool
    var ord: Int

    var createdAt: Date
    var updatedAt: Date
    var serverVersion: Int
    var deletedAt: Date?
    var syncStateRaw: Int

    init(
        id: String,
        ownerId: String,
        taskId: String,
        text: String,
        done: Bool = false,
        ord: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        syncStateRaw: Int = LocalSyncState.pendingCreate.rawValue
    ) {
        self.id = id
        self.ownerId = ownerId
        self.taskId = taskId
        self.text = text
        self.done = done
        self.ord = ord
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.syncStateRaw = syncStateRaw
    }
}

// MARK: - Routine (+ habit)

@Model
final class RoutineModel {
    @Attribute(.unique) var id: String
    var ownerId: String
    var name: String
    var colorHex: String
    var anchorTime: String?
    /// Encoded `RoutineRecurrence` JSON (kept as Data so the @Model stays simple).
    var recurrenceData: Data?
    var chained: Bool
    var isHabit: Bool
    var streakCurrent: Int
    var streakLongest: Int
    var graceDays: Int
    /// Encoded `[String]` of completion days ("YYYY-MM-DD") — server-owned.
    var completionsData: Data?
    /// Encoded `[RoutineStep]` JSON.
    var stepsData: Data?

    var createdAt: Date
    var updatedAt: Date
    var serverVersion: Int
    var deletedAt: Date?
    var syncStateRaw: Int

    init(
        id: String,
        ownerId: String,
        name: String,
        colorHex: String = "#4F46E5",
        anchorTime: String? = nil,
        recurrenceData: Data? = nil,
        chained: Bool = false,
        isHabit: Bool = false,
        streakCurrent: Int = 0,
        streakLongest: Int = 0,
        graceDays: Int = 0,
        completionsData: Data? = nil,
        stepsData: Data? = nil,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        syncStateRaw: Int = LocalSyncState.pendingCreate.rawValue
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.colorHex = colorHex
        self.anchorTime = anchorTime
        self.recurrenceData = recurrenceData
        self.chained = chained
        self.isHabit = isHabit
        self.streakCurrent = streakCurrent
        self.streakLongest = streakLongest
        self.graceDays = graceDays
        self.completionsData = completionsData
        self.stepsData = stepsData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.syncStateRaw = syncStateRaw
    }
}

// MARK: - Alarm

@Model
final class AlarmModel {
    @Attribute(.unique) var id: String
    var ownerId: String
    var taskId: String?
    var fireAt: Date?
    var type: Int
    var soundName: String?
    var snoozeMinutes: Int?
    var usesLiveActivity: Bool

    var createdAt: Date
    var updatedAt: Date
    var serverVersion: Int
    var deletedAt: Date?
    var syncStateRaw: Int

    init(
        id: String,
        ownerId: String,
        taskId: String? = nil,
        fireAt: Date? = nil,
        type: Int = 0,
        soundName: String? = nil,
        snoozeMinutes: Int? = nil,
        usesLiveActivity: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        syncStateRaw: Int = LocalSyncState.pendingCreate.rawValue
    ) {
        self.id = id
        self.ownerId = ownerId
        self.taskId = taskId
        self.fireAt = fireAt
        self.type = type
        self.soundName = soundName
        self.snoozeMinutes = snoozeMinutes
        self.usesLiveActivity = usesLiveActivity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.syncStateRaw = syncStateRaw
    }
}

/// Per-entity local sync state (AppSpec §6 `SyncState`). Kept in the app target (not SyncCore) since
/// it describes local persistence, not the wire contract.
enum LocalSyncState: Int, Codable, Sendable {
    case synced = 0
    case pendingCreate = 1
    case pendingUpdate = 2
    case pendingDelete = 3
}
