import Foundation

/// One-tap reschedule / snooze presets (FR-TASK-160). Pure date math so targets are deterministic and
/// unit-tested; `date(from:)` returns `nil` when a preset would land in the past so the UI can hide it.
public enum ReschedulePreset: String, CaseIterable, Sendable, Identifiable {
    case laterToday
    case thisEvening
    case tomorrow
    case thisWeekend
    case nextWeek

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .laterToday: return "Later today"
        case .thisEvening: return "This evening"
        case .tomorrow: return "Tomorrow"
        case .thisWeekend: return "This weekend"
        case .nextWeek: return "Next week"
        }
    }

    public var systemImage: String {
        switch self {
        case .laterToday: return "clock"
        case .thisEvening: return "moon"
        case .tomorrow: return "sun.max"
        case .thisWeekend: return "beach.umbrella"
        case .nextWeek: return "calendar"
        }
    }

    /// The target date for this preset relative to `now`, or `nil` if it would be in the past.
    /// Morning presets land at 09:00; "this evening" at 19:00; "later today" at the top of the hour
    /// three hours out. "This weekend" is the upcoming Saturday; "next week" is the upcoming Monday
    /// (the following Monday when today *is* Monday).
    public func date(from now: Date, calendar: Calendar = .current) -> Date? {
        let startOfDay = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: now) // 1=Sun … 7=Sat
        let result: Date?
        switch self {
        case .laterToday:
            let plus3 = calendar.date(byAdding: .hour, value: 3, to: now) ?? now
            result = calendar.date(bySettingHour: calendar.component(.hour, from: plus3), minute: 0, second: 0, of: plus3)
        case .thisEvening:
            result = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now)
        case .tomorrow:
            let tom = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
            result = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tom)
        case .thisWeekend:
            let delta = (7 - weekday + 7) % 7 // days to Saturday (0 if today is Saturday)
            let day = calendar.date(byAdding: .day, value: delta, to: startOfDay) ?? now
            result = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        case .nextWeek:
            var delta = (2 - weekday + 7) % 7 // days to Monday
            if delta == 0 { delta = 7 }       // today is Monday → next week's Monday
            let day = calendar.date(byAdding: .day, value: delta, to: startOfDay) ?? now
            result = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
        }
        guard let r = result, r > now else { return nil }
        return r
    }
}
