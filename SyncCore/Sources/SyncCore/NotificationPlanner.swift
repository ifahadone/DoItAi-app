import Foundation

/// One reminder resolved to a schedulable local notification (its task's title for the body).
public struct PlannedNotification: Equatable, Sendable, Identifiable {
    public var reminderId: String
    public var taskId: String
    public var fireAt: Date
    public var title: String

    public var id: String { reminderId }

    public init(reminderId: String, taskId: String, fireAt: Date, title: String) {
        self.reminderId = reminderId
        self.taskId = taskId
        self.fireAt = fireAt
        self.title = title
    }
}

/// Decides which reminders to schedule as local notifications (AppSpec §5.7, DevelopmentPlan P1-I).
///
/// iOS allows at most **64 pending** local notifications per app, silently dropping the rest. So we
/// schedule only the soonest-firing future reminders up to that cap and **re-arm** the rolling window
/// on every sync / foreground (as nearer ones fire or are added, the next batch moves in). Pure +
/// deterministic (injected `now`) so the windowing is unit-tested.
public enum NotificationPlanner {
    /// iOS's per-app pending-notification ceiling.
    public static let systemPendingCap = 64

    public static func plan(
        reminders: [PlannedNotification],
        now: Date,
        cap: Int = systemPendingCap
    ) -> [PlannedNotification] {
        reminders
            .filter { $0.fireAt > now }                 // only future fires
            .sorted { $0.fireAt < $1.fireAt }           // soonest first
            .prefix(max(0, cap))                        // rolling window
            .map { $0 }
    }
}
