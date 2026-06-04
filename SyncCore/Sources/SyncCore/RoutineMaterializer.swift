import Foundation

/// One materialized routine step — a task instance's title + its time block (minutes into the day).
public struct MaterializedStep: Equatable, Sendable {
    public var title: String
    public var startMinute: Int
    public var endMinute: Int
    public var ord: Int
    public var hasAlarm: Bool

    public init(title: String, startMinute: Int, endMinute: Int, ord: Int, hasAlarm: Bool) {
        self.title = title
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.ord = ord
        self.hasAlarm = hasAlarm
    }
}

/// Pure routine → day expansion (AppSpec §5.2 "Generation"; DevelopmentPlan P3-3). Decides whether a
/// routine occurs on a date and lays its steps out sequentially from the wall-clock anchor. Anchoring
/// to wall-clock minutes (not elapsed seconds) keeps it DST-correct — the caller builds the actual
/// `Date`s against the local calendar. Deterministic (injected `calendar`); the app handles idempotency
/// (skip if instances already exist) and id generation.
public enum RoutineMaterializer {
    /// Whether the routine occurs on `date`: weekday list (1=Sun…7=Sat) or every-N-days; nil = daily.
    public static func occurs(recurrence: RoutineRecurrence?, on date: Date, calendar: Calendar = .current) -> Bool {
        guard let recurrence else { return true }
        if let weekdays = recurrence.weekdays, !weekdays.isEmpty {
            return weekdays.contains(calendar.component(.weekday, from: date))
        }
        if let everyNDays = recurrence.everyNDays, everyNDays > 0 {
            let dayNumber = Int(calendar.startOfDay(for: date).timeIntervalSince1970 / 86_400)
            return dayNumber % everyNDays == 0
        }
        return true
    }

    /// The step instances laid out from `anchorTime` ("HH:mm"; defaults to 09:00), each starting where
    /// the previous ended (chained or not — the timeline is contiguous).
    public static func instances(steps: [RoutineStep], anchorTime: String?) -> [MaterializedStep] {
        var cursor = parseAnchorMinute(anchorTime) ?? (9 * 60)
        return steps.sorted { $0.ord < $1.ord }.map { step in
            let start = min(1440, cursor)
            let end = min(1440, start + max(1, step.minutes))
            cursor = end
            return MaterializedStep(title: step.title, startMinute: start, endMinute: end,
                                    ord: step.ord, hasAlarm: step.hasAlarm)
        }
    }

    /// Parse "HH:mm" (or "H:mm") into minutes-into-day. Nil if unparsable.
    public static func parseAnchorMinute(_ anchorTime: String?) -> Int? {
        guard let anchorTime, let colon = anchorTime.firstIndex(of: ":") else { return nil }
        guard let hour = Int(anchorTime[..<colon]),
              let minute = Int(anchorTime[anchorTime.index(after: colon)...]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}
