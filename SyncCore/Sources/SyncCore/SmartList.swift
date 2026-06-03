import Foundation

/// The built-in smart lists (AppSpec §5.4, DevelopmentPlan P1-G). A task that is *active* (not done or
/// cancelled) falls into EXACTLY ONE of these — a total, mutually-exclusive partition — so they double
/// as a triage funnel. Pure value type; the app filters its SwiftData rows through
/// ``SmartListClassifier`` so the UI and the golden-fixture test share one source of truth.
public enum SmartList: String, CaseIterable, Sendable, Identifiable {
    case overdue
    case today
    case upcoming
    case anytime
    case someday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        case .anytime: return "Anytime"
        case .someday: return "Someday"
        }
    }

    public var systemImage: String {
        switch self {
        case .overdue: return "exclamationmark.circle"
        case .today: return "sun.max"
        case .upcoming: return "calendar"
        case .anytime: return "tray"
        case .someday: return "archivebox"
        }
    }
}

public enum SmartListClassifier {
    /// Classify a task into its smart list, or `nil` when it is terminal (done/cancelled) and so
    /// belongs to none. A task's "date" is the earliest of `dueAt`/`scheduledStart`. Undated active
    /// tasks split by status: untriaged inbox → **Someday**, otherwise (committed) → **Anytime**.
    /// `now` is injected for determinism (AppSpec §16).
    public static func classify(
        status: TaskStatus,
        dueAt: Date?,
        scheduledStart: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> SmartList? {
        // Terminal states belong to no smart list.
        switch status {
        case .inbox, .scheduled, .inProgress: break
        case .done, .cancelled: return nil
        }

        let date = [dueAt, scheduledStart].compactMap { $0 }.min()
        guard let date else {
            return status == .inbox ? .someday : .anytime
        }

        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return .today
        }
        if date < startOfToday { return .overdue }
        if date < startOfTomorrow { return .today }
        return .upcoming
    }
}
