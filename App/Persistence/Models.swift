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

/// Per-entity local sync state (AppSpec §6 `SyncState`). Kept in the app target (not SyncCore) since
/// it describes local persistence, not the wire contract.
enum LocalSyncState: Int, Codable, Sendable {
    case synced = 0
    case pendingCreate = 1
    case pendingUpdate = 2
    case pendingDelete = 3
}
