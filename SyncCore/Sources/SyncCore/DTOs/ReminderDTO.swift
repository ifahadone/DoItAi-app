import Foundation

/// Wire representation of a reminder attached to a task (ApiSpec §5.7). Mirrors the server `reminders`
/// row + the SwiftData `Reminder` `@Model`. Phase 1 handles time-based reminders (`kind` 0 absolute /
/// 1 relative-to-due); location reminders (`kind` 2, server `region`) decode-through but aren't
/// scheduled yet, so `region` is intentionally omitted here (extra JSON keys are ignored on decode).
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }
}
