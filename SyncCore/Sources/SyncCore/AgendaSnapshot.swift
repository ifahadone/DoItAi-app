import Foundation

/// One row in the agenda widget. Pre-formatted by the app (the widget does no date/model logic).
public struct AgendaItem: Codable, Sendable, Equatable, Identifiable {
    public var taskId: String
    public var title: String
    public var dueText: String?
    public var isDone: Bool
    /// Wire priority level (0 none … 4 p1) for the widget's flag.
    public var priorityLevel: Int
    /// Scheduled block start/end as minutes-into-day, for the sectograph widget's dial (P2-6). Optional
    /// (decode-safe for older snapshots) and `nil` for due-only items.
    public var startMinute: Int?
    public var endMinute: Int?
    /// The task's list color (hex), for the dial block + the agenda row's color bar. Nil = use accent.
    public var colorHex: String?

    public var id: String { taskId }

    public init(taskId: String, title: String, dueText: String? = nil, isDone: Bool = false,
                priorityLevel: Int = 0, startMinute: Int? = nil, endMinute: Int? = nil, colorHex: String? = nil) {
        self.taskId = taskId
        self.title = title
        self.dueText = dueText
        self.isDone = isDone
        self.priorityLevel = priorityLevel
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.colorHex = colorHex
    }

    // Decode-safe: tolerate snapshots written by an older app build that lacks the newer keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try c.decode(String.self, forKey: .taskId)
        title = try c.decode(String.self, forKey: .title)
        dueText = try c.decodeIfPresent(String.self, forKey: .dueText)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        priorityLevel = try c.decodeIfPresent(Int.self, forKey: .priorityLevel) ?? 0
        startMinute = try c.decodeIfPresent(Int.self, forKey: .startMinute)
        endMinute = try c.decodeIfPresent(Int.self, forKey: .endMinute)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
    }
}

/// A habit summary for the Streak widget: name, current streak, and the last-N days' completion bits
/// (oldest → newest) for the mini heatmap.
public struct HabitSummary: Codable, Sendable, Equatable {
    public var name: String
    public var streakCurrent: Int
    public var recent: [Bool]

    public init(name: String, streakCurrent: Int, recent: [Bool]) {
        self.name = name
        self.streakCurrent = streakCurrent
        self.recent = recent
    }
}

/// The data the app publishes for the widgets (DevelopmentPlan P1-J / P2-6). Snapshot pattern: the app
/// writes this to the shared App-Group store on each sync; the WidgetKit extension reads it. This
/// decouples the widgets from SwiftData/the app target — they only need `SyncCore`.
public struct AgendaSnapshot: Codable, Sendable, Equatable {
    public var items: [AgendaItem]
    /// When the snapshot was produced (epoch seconds; the app stamps it — `SyncCore` avoids `Date()`).
    public var generatedAtEpoch: Double
    /// Today's completed / total task counts, for the "X of Y done" progress ring.
    public var completedToday: Int
    public var totalToday: Int
    /// Minutes focused today (sum of `actualMinutes` on today's tasks), for the focus stat.
    public var focusMinutesToday: Int
    /// The highest-streak habit, for the Streak widget (nil if no habits).
    public var topHabit: HabitSummary?

    public init(items: [AgendaItem], generatedAtEpoch: Double,
                completedToday: Int = 0, totalToday: Int = 0, focusMinutesToday: Int = 0,
                topHabit: HabitSummary? = nil) {
        self.items = items
        self.generatedAtEpoch = generatedAtEpoch
        self.completedToday = completedToday
        self.totalToday = totalToday
        self.focusMinutesToday = focusMinutesToday
        self.topHabit = topHabit
    }

    // Decode-safe: an older snapshot (pre-enrichment) decodes with zeroed counts + no habit.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([AgendaItem].self, forKey: .items) ?? []
        generatedAtEpoch = try c.decodeIfPresent(Double.self, forKey: .generatedAtEpoch) ?? 0
        completedToday = try c.decodeIfPresent(Int.self, forKey: .completedToday) ?? 0
        totalToday = try c.decodeIfPresent(Int.self, forKey: .totalToday) ?? 0
        focusMinutesToday = try c.decodeIfPresent(Int.self, forKey: .focusMinutesToday) ?? 0
        topHabit = try c.decodeIfPresent(HabitSummary.self, forKey: .topHabit)
    }

    public static let empty = AgendaSnapshot(items: [], generatedAtEpoch: 0)
}

/// Reads/writes an ``AgendaSnapshot`` to a shared `UserDefaults` (App-Group suite). Pure: the caller
/// supplies the `UserDefaults` (the app uses `UserDefaults(suiteName: appGroup)`, the widget the same).
public enum AgendaSnapshotStore {
    public static let defaultKey = "doit.agenda.snapshot.v1"

    public static func save(_ snapshot: AgendaSnapshot, to defaults: UserDefaults, key: String = defaultKey) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    public static func load(from defaults: UserDefaults, key: String = defaultKey) -> AgendaSnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(AgendaSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
