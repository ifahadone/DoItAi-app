import Foundation

/// Wire representation of a task. Mirrors the server `tasks` table (ApiSpec §5.1) and the SwiftData
/// `Task` `@Model` (AppSpec §6) field-for-field.
///
/// - IDs are client-generated UUID strings (`String`, not `UUID`, so they survive offline→sync with
///   no remap and match the JSON exactly — ApiSpec §3 / §6).
/// - All timestamps are UTC `Date` instants.
/// - `tagIds` is the flattened M:N relationship (server `task_tags`); the SwiftData layer rehydrates
///   it into `@Relationship var tags`.
/// - `serverVersion` guards lost updates; `deletedAt` is the soft-delete tombstone.
///
/// Unknown server fields are ignored on decode and absent client fields are omitted on encode
/// (additive-contract rule, ApiSpec §13) — the default `Codable` synthesis already does both.
public struct TaskDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var listId: String?
    public var parentTaskId: String?

    public var title: String
    public var notes: String?
    public var status: TaskStatus
    public var priority: Priority
    public var rank: Int
    public var energy: Energy?

    // Scheduling
    public var dueAt: Date?
    public var scheduledStart: Date?
    public var scheduledEnd: Date?
    public var estimatedMinutes: Int?
    public var actualMinutes: Int?
    public var isAllDay: Bool

    // Recurrence
    public var recurrence: RecurrenceRule?
    public var recurrenceParentId: String?
    public var routineInstanceOf: String?

    // Relationships / collaboration
    public var assigneeUserId: String?
    public var location: GeoPoint?
    public var url: String?
    public var tagIds: [String]

    // Audit / sync
    public var createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?
    public var archived: Bool
    public var serverVersion: Int
    public var deletedAt: Date?

    public init(
        id: String,
        ownerId: String,
        listId: String? = nil,
        parentTaskId: String? = nil,
        title: String,
        notes: String? = nil,
        status: TaskStatus = .inbox,
        priority: Priority = .none,
        rank: Int = 0,
        energy: Energy? = nil,
        dueAt: Date? = nil,
        scheduledStart: Date? = nil,
        scheduledEnd: Date? = nil,
        estimatedMinutes: Int? = nil,
        actualMinutes: Int? = nil,
        isAllDay: Bool = false,
        recurrence: RecurrenceRule? = nil,
        recurrenceParentId: String? = nil,
        routineInstanceOf: String? = nil,
        assigneeUserId: String? = nil,
        location: GeoPoint? = nil,
        url: String? = nil,
        tagIds: [String] = [],
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil,
        archived: Bool = false,
        serverVersion: Int = 0,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.listId = listId
        self.parentTaskId = parentTaskId
        self.title = title
        self.notes = notes
        self.status = status
        self.priority = priority
        self.rank = rank
        self.energy = energy
        self.dueAt = dueAt
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.recurrenceParentId = recurrenceParentId
        self.routineInstanceOf = routineInstanceOf
        self.assigneeUserId = assigneeUserId
        self.location = location
        self.url = url
        self.tagIds = tagIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.archived = archived
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }
}
