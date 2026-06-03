import Foundation

/// An RFC-5545 subset recurrence rule (AppSpec §6, ApiSpec §5.3).
///
/// Stored server-side as JSONB in `tasks.recurrence`; carried in ``TaskDTO/recurrence``.
/// The server never expands recurrences into instants — materialization is client-side and
/// DST-correct (ApiSpec §6.5, §11). This is a pure data shape.
public struct RecurrenceRule: Codable, Sendable, Equatable {
    /// Frequency of recurrence. String-valued on the wire (ApiSpec §5.3 example).
    public enum Freq: String, Codable, Sendable {
        case daily
        case weekly
        case monthly
        case yearly
    }

    public var freq: Freq
    /// Repeat every N periods (e.g. every 2 weeks). Must be >= 1.
    public var interval: Int
    /// Days of week the rule applies to. Convention: 1 = Sun … 7 = Sat (AppSpec §6).
    public var byWeekday: [Int]?
    /// Days of month (1…31, negative = from end) the rule applies to.
    public var byMonthDay: [Int]?
    /// Total number of occurrences, if bounded by count.
    public var count: Int?
    /// End date (UTC), if bounded by an until-date.
    public var until: Date?

    public init(
        freq: Freq,
        interval: Int = 1,
        byWeekday: [Int]? = nil,
        byMonthDay: [Int]? = nil,
        count: Int? = nil,
        until: Date? = nil
    ) {
        self.freq = freq
        self.interval = interval
        self.byWeekday = byWeekday
        self.byMonthDay = byMonthDay
        self.count = count
        self.until = until
    }
}
