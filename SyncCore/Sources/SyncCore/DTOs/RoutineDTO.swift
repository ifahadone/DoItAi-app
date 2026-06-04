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
    /// Completed days ("YYYY-MM-DD") — server-owned (POST /habits/{id}/log); read-only on the client.
    public var completions: [String]
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
        completions: [String] = [],
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
        self.completions = completions
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }

    /// Forward-compatible decode: tolerate change_log payloads written before a field existed (e.g.
    /// `completions`/`steps` on routines created earlier) by defaulting them, so an old entry never
    /// aborts the whole pull (additive-contract rule, ApiSpec §13).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        ownerId = try c.decode(String.self, forKey: .ownerId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#4F46E5"
        anchorTime = try c.decodeIfPresent(String.self, forKey: .anchorTime)
        recurrence = try c.decodeIfPresent(RoutineRecurrence.self, forKey: .recurrence)
        chained = try c.decodeIfPresent(Bool.self, forKey: .chained) ?? false
        isHabit = try c.decodeIfPresent(Bool.self, forKey: .isHabit) ?? false
        streakCurrent = try c.decodeIfPresent(Int.self, forKey: .streakCurrent) ?? 0
        streakLongest = try c.decodeIfPresent(Int.self, forKey: .streakLongest) ?? 0
        graceDays = try c.decodeIfPresent(Int.self, forKey: .graceDays) ?? 0
        completions = try c.decodeIfPresent([String].self, forKey: .completions) ?? []
        steps = try c.decodeIfPresent([RoutineStep].self, forKey: .steps) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        serverVersion = try c.decodeIfPresent(Int.self, forKey: .serverVersion) ?? 0
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}
