import Foundation

/// One task projected to the fields analytics needs (AppSpec §5.9). Pure value type so the aggregation
/// lives in `SyncCore` and is unit-tested; the app maps its `TaskModel`s into these.
public struct TaskStat: Sendable, Equatable {
    public var id: String
    public var isDone: Bool
    public var createdAt: Date
    public var dueAt: Date?
    /// When the task was completed (the app passes `updatedAt` for done tasks). Nil if not done.
    public var completedAt: Date?
    public var scheduledStart: Date?
    public var scheduledEnd: Date?
    public var actualMinutes: Int?
    public var listId: String?

    public init(id: String, isDone: Bool, createdAt: Date, dueAt: Date? = nil, completedAt: Date? = nil,
                scheduledStart: Date? = nil, scheduledEnd: Date? = nil, actualMinutes: Int? = nil, listId: String? = nil) {
        self.id = id
        self.isDone = isDone
        self.createdAt = createdAt
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.actualMinutes = actualMinutes
        self.listId = listId
    }

    /// Planned minutes from a scheduled block, if both ends are set.
    public var plannedMinutes: Int? {
        guard let s = scheduledStart, let e = scheduledEnd, e > s else { return nil }
        return Int(e.timeIntervalSince(s) / 60)
    }
}

/// Pure analytics aggregations over `TaskStat`s (AppSpec §5.9). All on-device, deterministic, tested.
public enum Analytics {
    // MARK: Completion

    public struct Completion: Equatable, Sendable {
        public var created: Int
        public var completed: Int
        public var overdue: Int
        /// completed ÷ created over the range, 0–100 (nil when nothing was created).
        public var completionRatePct: Int?
        /// of the completed-in-range tasks, % finished on or before their due date (nil if none had a due).
        public var onTimePct: Int?
    }

    public static func completion(_ tasks: [TaskStat], in range: DateInterval, now: Date) -> Completion {
        let created = tasks.filter { range.contains($0.createdAt) }.count
        let completedTasks = tasks.filter { $0.isDone && ($0.completedAt.map { range.contains($0) } ?? false) }
        let completed = completedTasks.count
        let overdue = tasks.filter { !$0.isDone && ($0.dueAt.map { $0 < now } ?? false) }.count

        let rate = created > 0 ? Int((Double(completed) / Double(created) * 100).rounded()) : nil
        let withDue = completedTasks.filter { $0.dueAt != nil }
        let onTime: Int? = withDue.isEmpty
            ? nil
            : Int((Double(withDue.filter { ($0.completedAt ?? .distantFuture) <= ($0.dueAt ?? .distantPast) }.count) / Double(withDue.count) * 100).rounded())
        return Completion(created: created, completed: completed, overdue: overdue, completionRatePct: rate, onTimePct: onTime)
    }

    // MARK: Productivity by hour (completion heatmap)

    /// 24 buckets (index = hour 0–23) of how many tasks were completed in that hour of the day.
    public static func productivityByHour(_ tasks: [TaskStat], calendar: Calendar) -> [Int] {
        var buckets = [Int](repeating: 0, count: 24)
        for task in tasks where task.isDone {
            guard let done = task.completedAt else { continue }
            let hour = calendar.component(.hour, from: done)
            if (0..<24).contains(hour) { buckets[hour] += 1 }
        }
        return buckets
    }

    /// The peak completion hour (nil when there's no completion data).
    public static func peakHour(_ tasks: [TaskStat], calendar: Calendar) -> Int? {
        let buckets = productivityByHour(tasks, calendar: calendar)
        guard let max = buckets.max(), max > 0 else { return nil }
        return buckets.firstIndex(of: max)
    }

    // MARK: Time allocation

    public struct TimeSlice: Equatable, Sendable, Identifiable {
        public var listId: String?
        public var minutes: Int
        public var id: String { listId ?? "—" }
    }

    /// Minutes per list, using actual focus minutes where present, else the planned block length.
    /// Sorted descending; tasks with no time contribution are skipped.
    public static func timeByList(_ tasks: [TaskStat]) -> [TimeSlice] {
        var totals: [String: Int] = [:]
        let noList = "\u{0}none"
        for task in tasks {
            let minutes = task.actualMinutes ?? task.plannedMinutes ?? 0
            guard minutes > 0 else { continue }
            totals[task.listId ?? noList, default: 0] += minutes
        }
        return totals
            .map { TimeSlice(listId: $0.key == noList ? nil : $0.key, minutes: $0.value) }
            .sorted { $0.minutes > $1.minutes }
    }

    // MARK: Backlog health

    public struct Backlog: Equatable, Sendable {
        public var inbox: Int // open (not done) tasks
        public var overdue: Int
        public var medianAgeDays: Int
    }

    public static func backlog(_ tasks: [TaskStat], now: Date) -> Backlog {
        let open = tasks.filter { !$0.isDone }
        let overdue = open.filter { $0.dueAt.map { $0 < now } ?? false }.count
        let ages = open.map { Int(now.timeIntervalSince($0.createdAt) / 86_400) }.sorted()
        let median: Int
        if ages.isEmpty {
            median = 0
        } else if ages.count % 2 == 1 {
            median = ages[ages.count / 2]
        } else {
            median = (ages[ages.count / 2 - 1] + ages[ages.count / 2]) / 2
        }
        return Backlog(inbox: open.count, overdue: overdue, medianAgeDays: median)
    }

    // MARK: Focus

    public struct Focus: Equatable, Sendable {
        public var totalMinutes: Int
        public var sessions: Int
        public var avgMinutes: Int
    }

    public static func focus(_ tasks: [TaskStat]) -> Focus {
        let focused = tasks.compactMap { $0.actualMinutes }.filter { $0 > 0 }
        let total = focused.reduce(0, +)
        return Focus(totalMinutes: total, sessions: focused.count, avgMinutes: focused.isEmpty ? 0 : total / focused.count)
    }
}
