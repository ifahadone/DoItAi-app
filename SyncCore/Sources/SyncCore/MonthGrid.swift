import Foundation

/// A month's calendar grid for the month view (Apple-Calendar style): always 6 weeks × 7 days so the
/// layout doesn't jump between months, with leading/trailing days from adjacent months flagged. Pure +
/// deterministic so it's unit-tested.
public struct MonthGrid: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        public var date: Date          // start-of-day
        public var inMonth: Bool       // belongs to the displayed month (vs. a leading/trailing spill day)
        public var id: Date { date }
        public init(date: Date, inMonth: Bool) { self.date = date; self.inMonth = inMonth }
    }

    /// Start-of-day of the displayed month's first day.
    public var monthStart: Date
    /// 6 rows of 7 days, each row a calendar week starting on the calendar's `firstWeekday`.
    public var weeks: [[Day]]
    /// Weekday header symbols (e.g. ["S","M",…]) in display order, matching `firstWeekday`.
    public var weekdaySymbols: [String]

    public init(monthStart: Date, weeks: [[Day]], weekdaySymbols: [String]) {
        self.monthStart = monthStart
        self.weeks = weeks
        self.weekdaySymbols = weekdaySymbols
    }
}

public enum MonthGridBuilder {
    /// Build the 6×7 grid for the month containing `date`.
    public static func make(for date: Date, calendar: Calendar = .current) -> MonthGrid {
        let startOfDay = calendar.startOfDay(for: date)
        let comps = calendar.dateComponents([.year, .month], from: startOfDay)
        let monthStart = calendar.date(from: comps) ?? startOfDay

        // Step back from the 1st to the grid's first cell (the `firstWeekday` of that week).
        let firstWeekdayIndex = calendar.component(.weekday, from: monthStart) // 1…7
        let lead = (firstWeekdayIndex - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -lead, to: monthStart) ?? monthStart

        let displayedMonth = calendar.component(.month, from: monthStart)
        var weeks: [[MonthGrid.Day]] = []
        for week in 0..<6 {
            var row: [MonthGrid.Day] = []
            for weekday in 0..<7 {
                let offset = week * 7 + weekday
                let day = calendar.date(byAdding: .day, value: offset, to: gridStart) ?? gridStart
                let inMonth = calendar.component(.month, from: day) == displayedMonth
                row.append(MonthGrid.Day(date: calendar.startOfDay(for: day), inMonth: inMonth))
            }
            weeks.append(row)
        }

        // Weekday header symbols rotated to start at `firstWeekday`.
        let symbols = calendar.veryShortWeekdaySymbols // index 0 = Sunday
        let ordered = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }

        return MonthGrid(monthStart: monthStart, weeks: weeks, weekdaySymbols: ordered)
    }
}
