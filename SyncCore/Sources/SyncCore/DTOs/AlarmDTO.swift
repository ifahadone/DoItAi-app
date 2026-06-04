import Foundation

/// Wire representation of a time-critical alarm (ApiSpec §5.6, §7.5). The client owns delivery (the
/// iOS reality caveat — Time-Sensitive/Critical notifications + Live Activity, not a true system
/// alarm); the server just stores it. `taskId` is nil for a standalone wake alarm.
public struct AlarmDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var taskId: String?
    public var fireAt: Date?
    /// 0 wake · 1 taskStart · 2 routineStep · 3 leaveBy.
    public var type: Int
    public var soundName: String?
    public var snoozeMinutes: Int?
    public var usesLiveActivity: Bool

    public var createdAt: Date
    public var updatedAt: Date
    public var serverVersion: Int
    public var deletedAt: Date?

    public init(
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
        deletedAt: Date? = nil
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
        self.deletedAt = deletedAt
    }
}
