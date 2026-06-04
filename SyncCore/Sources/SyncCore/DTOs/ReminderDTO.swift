import Foundation

/// Wire representation of a reminder attached to a task (ApiSpec §5.7). Mirrors the server `reminders`
/// row + the SwiftData `Reminder` `@Model`. Handles time-based reminders (`kind` 0 absolute /
/// 1 relative-to-due) and location reminders (`kind` 2, geofenced via `region`; see `GeofencePlanner`).
public struct ReminderDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var taskId: String
    /// 0 absolute · 1 relativeToDue · 2 location · 3 recurring.
    public var kind: Int
    /// Absolute fire time (for `kind` 0). Null for relative/location reminders.
    public var fireAt: Date?
    /// Minutes before the task's due date (for `kind` 1).
    public var offsetMinutes: Int?
    /// 0 passive · 1 active · 2 timeSensitive · 3 critical.
    public var interruption: Int
    /// The scheduled `UNNotificationRequest` identifier, if currently scheduled locally.
    public var notificationId: String?
    /// Geofence for a location reminder (`kind` 2). Null for time-based reminders.
    public var region: ReminderRegion?

    public var createdAt: Date
    public var updatedAt: Date
    public var serverVersion: Int
    public var deletedAt: Date?

    public init(
        id: String,
        ownerId: String,
        taskId: String,
        kind: Int = 0,
        fireAt: Date? = nil,
        offsetMinutes: Int? = nil,
        interruption: Int = 1,
        notificationId: String? = nil,
        region: ReminderRegion? = nil,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.taskId = taskId
        self.kind = kind
        self.fireAt = fireAt
        self.offsetMinutes = offsetMinutes
        self.interruption = interruption
        self.notificationId = notificationId
        self.region = region
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }

    /// Forward-compatible decode: reminders written before `region` existed (kind 0/1) simply have no
    /// `region` key, so default it to nil rather than aborting the pull (additive-contract, ApiSpec §13).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ownerId = try c.decode(String.self, forKey: .ownerId)
        taskId = try c.decode(String.self, forKey: .taskId)
        kind = try c.decodeIfPresent(Int.self, forKey: .kind) ?? 0
        fireAt = try c.decodeIfPresent(Date.self, forKey: .fireAt)
        offsetMinutes = try c.decodeIfPresent(Int.self, forKey: .offsetMinutes)
        interruption = try c.decodeIfPresent(Int.self, forKey: .interruption) ?? 1
        notificationId = try c.decodeIfPresent(String.self, forKey: .notificationId)
        region = try c.decodeIfPresent(ReminderRegion.self, forKey: .region)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        serverVersion = try c.decodeIfPresent(Int.self, forKey: .serverVersion) ?? 0
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}
