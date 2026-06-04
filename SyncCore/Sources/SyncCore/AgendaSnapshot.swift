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

    public var id: String { taskId }

    public init(taskId: String, title: String, dueText: String? = nil, isDone: Bool = false,
                priorityLevel: Int = 0, startMinute: Int? = nil, endMinute: Int? = nil) {
        self.taskId = taskId
        self.title = title
        self.dueText = dueText
        self.isDone = isDone
        self.priorityLevel = priorityLevel
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

/// The data the app publishes for the agenda widget (DevelopmentPlan P1-J). Snapshot pattern: the app
/// writes this to the shared App-Group store on each sync; the WidgetKit extension reads it. This
/// decouples the widget from SwiftData/the app target — the widget only needs `SyncCore`.
public struct AgendaSnapshot: Codable, Sendable, Equatable {
    public var items: [AgendaItem]
    /// When the snapshot was produced (epoch seconds; the app stamps it — `SyncCore` avoids `Date()`).
    public var generatedAtEpoch: Double

    public init(items: [AgendaItem], generatedAtEpoch: Double) {
        self.items = items
        self.generatedAtEpoch = generatedAtEpoch
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
