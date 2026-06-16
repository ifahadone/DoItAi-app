import Foundation

/// Computes the next occurrence of a task ``RecurrenceRule`` (client-side; the server never expands
/// recurrences — ApiSpec §6.5). Pure + DST-correct via `Calendar`, so it's deterministic + unit-tested.
///
/// Expansion order (FR-RECUR-050):
/// - `byWeekday` present  → the next day whose weekday is in the set, gated to "on" weeks by `interval`;
/// - else `byMonthDay`    → the next day whose day-of-month matches (negative counts from month end),
///                          gated to "on" months by `interval`;
/// - else                 → plain `freq` + `interval` stepping.
/// The `until` bound and the `count` bound (via `occurrencesSoFar`) are honored in all paths. Times of
/// day are preserved from the prior occurrence so a 9:00 AM task stays at 9:00 AM across DST.
public enum RecurrenceEngine {
    /// The next due date strictly after `date` per `rule`, or `nil` if the rule has ended (past `until`,
    /// or `occurrencesSoFar` has reached `count`). `occurrencesSoFar` is how many instances of the series
    /// already exist (the materializer passes this so a `count`-bounded rule stops; omit it when unknown).
    public static func nextOccurrence(after date: Date, rule: RecurrenceRule,
                                      calendar: Calendar = .current,
                                      occurrencesSoFar: Int? = nil) -> Date? {
        if let count = rule.count, let made = occurrencesSoFar, made >= count { return nil }

        let interval = max(1, rule.interval)
        let next: Date?
        if let weekdays = rule.byWeekday, !weekdays.isEmpty {
            next = nextByWeekday(after: date, weekdays: Set(weekdays), interval: interval, calendar: calendar)
        } else if let monthDays = rule.byMonthDay, !monthDays.isEmpty {
            next = nextByMonthDay(after: date, monthDays: monthDays, interval: interval, calendar: calendar)
        } else {
            next = stepByFreq(after: date, freq: rule.freq, interval: interval, calendar: calendar)
        }
        guard let result = next else { return nil }
        if let until = rule.until, result > until { return nil }
        return result
    }

    // MARK: - Expansion paths

    private static func stepByFreq(after date: Date, freq: RecurrenceRule.Freq, interval: Int,
                                   calendar: Calendar) -> Date? {
        let component: Calendar.Component
        switch freq {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        }
        return calendar.date(byAdding: component, value: interval, to: date)
    }

    /// Next day strictly after `date` whose weekday (1=Sun…7=Sat, matching `Calendar`) is in `weekdays`.
    /// For `interval > 1`, candidate weeks must be a multiple of `interval` weeks from the reference week.
    private static func nextByWeekday(after date: Date, weekdays: Set<Int>, interval: Int,
                                      calendar: Calendar) -> Date? {
        let refDay = calendar.startOfDay(for: date)
        let refWeek = calendar.dateInterval(of: .weekOfYear, for: refDay)?.start
        for offset in 1...371 { // up to ~53 weeks — enough for any weekly interval
            guard let day = calendar.date(byAdding: .day, value: offset, to: refDay) else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            if interval > 1, let refWeek, let candWeek = calendar.dateInterval(of: .weekOfYear, for: day)?.start {
                let weeks = calendar.dateComponents([.weekOfYear], from: refWeek, to: candWeek).weekOfYear ?? 0
                if weeks % interval != 0 { continue }
            }
            return applyingTime(of: date, to: day, calendar: calendar)
        }
        return nil
    }

    /// Next day strictly after `date` whose day-of-month matches one of `monthDays` (positive = from
    /// start, negative = from end: -1 is the last day). For `interval > 1`, candidate months must be a
    /// multiple of `interval` months from the reference month.
    private static func nextByMonthDay(after date: Date, monthDays: [Int], interval: Int,
                                       calendar: Calendar) -> Date? {
        let refDay = calendar.startOfDay(for: date)
        let refMonth = calendar.dateInterval(of: .month, for: refDay)?.start
        for offset in 1...750 { // ~2 years — covers sparse month-days with larger intervals
            guard let day = calendar.date(byAdding: .day, value: offset, to: refDay) else { continue }
            guard let range = calendar.range(of: .day, in: .month, for: day) else { continue }
            let daysInMonth = range.count
            let dom = calendar.component(.day, from: day)
            let matches = monthDays.contains { md in md > 0 ? md == dom : (daysInMonth + md + 1) == dom }
            guard matches else { continue }
            if interval > 1, let refMonth, let candMonth = calendar.dateInterval(of: .month, for: day)?.start {
                let months = calendar.dateComponents([.month], from: refMonth, to: candMonth).month ?? 0
                if months % interval != 0 { continue }
            }
            return applyingTime(of: date, to: day, calendar: calendar)
        }
        return nil
    }

    /// Carry the hour/minute/second of `source` onto the calendar `day` (midnight) so recurrences keep
    /// their time of day.
    private static func applyingTime(of source: Date, to day: Date, calendar: Calendar) -> Date {
        let t = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: t.second ?? 0, of: day) ?? day
    }
}
