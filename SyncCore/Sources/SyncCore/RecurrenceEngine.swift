import Foundation

/// Computes the next occurrence of a task ``RecurrenceRule`` (client-side; the server never expands
/// recurrences — ApiSpec §6.5). Pure + DST-correct via `Calendar`, so it's deterministic + unit-tested.
///
/// v1 expands `freq` + `interval` and honors the `until` bound. The `byWeekday` / `byMonthDay` / `count`
/// refinements are carried in the rule but not yet expanded here (the task recurrence picker only sets
/// freq+interval today).
public enum RecurrenceEngine {
    /// The next due date strictly after `date` per `rule`, or `nil` if the rule has ended (past `until`).
    public static func nextOccurrence(after date: Date, rule: RecurrenceRule,
                                      calendar: Calendar = .current) -> Date? {
        let interval = max(1, rule.interval)
        let component: Calendar.Component
        switch rule.freq {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        }
        guard let next = calendar.date(byAdding: component, value: interval, to: date) else { return nil }
        if let until = rule.until, next > until { return nil }
        return next
    }
}
