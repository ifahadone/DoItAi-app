import Foundation

/// One step of a routine (ApiSpec §5.2). Embedded in ``RoutineDTO.steps`` (no separate entity).
public struct RoutineStep: Codable, Sendable, Equatable, Identifiable {
    public var title: String
    public var minutes: Int
    public var ord: Int
    public var hasAlarm: Bool

    public var id: Int { ord }

    public init(title: String, minutes: Int, ord: Int, hasAlarm: Bool = false) {
        self.title = title
        self.minutes = minutes
        self.ord = ord
        self.hasAlarm = hasAlarm
    }
}

/// A routine's recurrence (ApiSpec §5.2): either specific `weekdays` (1=Sun…7=Sat) or `everyNDays`.
public struct RoutineRecurrence: Codable, Sendable, Equatable {
    public var weekdays: [Int]?
    public var everyNDays: Int?

    public init(weekdays: [Int]? = nil, everyNDays: Int? = nil) {
        self.weekdays = weekdays
        self.everyNDays = everyNDays
    }
}

/// Wire representation of a routine — a recurring step template, or (with `isHabit: true`) a tracked
/// habit. Mirrors the server `routines` row. Streak fields are server-authoritative (advanced via
/// `POST /habits/{id}/log`); the client reads but doesn't write them through sync.
public struct RoutineDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var name: String
    public var colorHex: String
    /// Wall-clock anchor "HH:mm" (materialized client-side, DST-safe). Nil = unscheduled.
    public var anchorTime: String?
    public var recurrence: RoutineRecurrence?
    public var chained: Bool
    public var isHabit: Bool
    public var streakCurrent: Int
    public var streakLongest: Int
    public var graceDays: Int
    public var steps: [RoutineStep]

    public var createdAt: Date
    public var updatedAt: Date
    public var serverVersion: Int
    public var deletedAt: Date?

    public init(
        id: String,
        ownerId: String,
        name: String,
        colorHex: String = "#4F46E5",
        anchorTime: String? = nil,
        recurrence: RoutineRecurrence? = nil,
        chained: Bool = false,
        isHabit: Bool = false,
        streakCurrent: Int = 0,
        streakLongest: Int = 0,
        graceDays: Int = 0,
        steps: [RoutineStep] = [],
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.colorHex = colorHex
        self.anchorTime = anchorTime
        self.recurrence = recurrence
        self.chained = chained
        self.isHabit = isHabit
        self.streakCurrent = streakCurrent
        self.streakLongest = streakLongest
        self.graceDays = graceDays
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }
}
