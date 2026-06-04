import Foundation

/// One day in a habit's "don't break the chain" heatmap (AppSpec §5.2, DevelopmentPlan P3-5).
public struct HeatmapDay: Equatable, Sendable, Identifiable {
    /// Days relative to today (0 = today, -1 = yesterday …).
    public var dayOffset: Int
    public var dateString: String
    public var completed: Bool

    public var id: Int { dayOffset }

    public init(dayOffset: Int, dateString: String, completed: Bool) {
        self.dayOffset = dayOffset
        self.dateString = dateString
        self.completed = completed
    }
}

/// Builds the heatmap grid data for a habit. Pure (injected `today`/`calendar`) so the layout is
/// deterministic and unit-tested; the view just renders the cells.
public enum HabitHeatmap {
    /// The last `days` days ending today (oldest first), each marked completed (from the habit's
    /// `completions` `YYYY-MM-DD` set) or not.
    public static func days(completions: Set<String>, days: Int, today: Date, calendar: Calendar = .current) -> [HeatmapDay] {
        guard days > 0 else { return [] }
        return (0..<days).reversed().map { stepsBack in
            let offset = -stepsBack
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let dateString = isoDay(date, calendar)
            return HeatmapDay(dayOffset: offset, dateString: dateString, completed: completions.contains(dateString))
        }
    }

    /// Count of completions within the window (for a quick "N of last D days" stat).
    public static func completedCount(in days: [HeatmapDay]) -> Int {
        days.reduce(0) { $0 + ($1.completed ? 1 : 0) }
    }

    static func isoDay(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
