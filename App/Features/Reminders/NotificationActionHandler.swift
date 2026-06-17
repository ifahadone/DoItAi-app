import Foundation
import SwiftData
import UserNotifications
import SyncCore

/// Makes local reminder notifications *actionable* (AppSpec §5.7, DevelopmentPlan P1-I). Previously a
/// fired reminder was a passive banner; now it carries **Complete** and **Snooze 10 min** buttons, and
/// this object is the `UNUserNotificationCenterDelegate` that turns a tapped action into a real
/// ``TaskMutation`` (so completing from the lock screen syncs like any other edit) and re-presents
/// banners while the app is foregrounded.
///
/// Registered once at launch (``DoITApp``). The center holds its delegate weakly, so ``DoITApp`` retains
/// this instance for the process lifetime. Action handling hops to the `@MainActor` since it touches the
/// SwiftData `mainContext` + the main-actor ``TaskMutation`` / ``AppServices``.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    static let categoryId = "DOIT_REMINDER"
    static let completeActionId = "DOIT_COMPLETE"
    static let snoozeActionId = "DOIT_SNOOZE"
    static let rescheduleActionId = "DOIT_RESCHEDULE"
    static let snoozeInterval: TimeInterval = 10 * 60

    private let container: ModelContainer
    private let services: AppServices

    init(container: ModelContainer, services: AppServices) {
        self.container = container
        self.services = services
        super.init()
    }

    /// Install the delegate + register the reminder category's action buttons. Idempotent; no permission
    /// prompt (that's separate — see ``AppServices/requestNotificationAuthorization()``).
    func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let complete = UNNotificationAction(identifier: Self.completeActionId, title: "Complete", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeActionId, title: "Snooze 10 min", options: [])
        let reschedule = UNNotificationAction(identifier: Self.rescheduleActionId, title: "Tomorrow", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryId, actions: [complete, snooze, reschedule],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show reminder banners even while the app is in the foreground (otherwise iOS suppresses them).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Route a tapped action button to a task mutation.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard let taskId = content.userInfo["taskId"] as? String else { return }
        await handle(actionId: response.actionIdentifier, taskId: taskId, title: content.title)
    }

    @MainActor
    private func handle(actionId: String, taskId: String, title: String) async {
        switch actionId {
        case Self.completeActionId:
            let ctx = container.mainContext
            var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == taskId })
            descriptor.fetchLimit = 1
            guard let task = try? ctx.fetch(descriptor).first, task.status != .done else { return }
            let mutation = TaskMutation(context: ctx, engine: services.syncEngine,
                                        clock: services.clock, idGenerator: services.idGenerator)
            await mutation.toggleComplete(task)
            if AppConfig.isLiveSync { await services.syncOnce() } // push the completion promptly
        case Self.snoozeActionId:
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = "Snoozed reminder"
            content.sound = .default
            content.categoryIdentifier = Self.categoryId
            content.userInfo = ["taskId": taskId]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.snoozeInterval, repeats: false)
            let request = UNNotificationRequest(identifier: "snooze-\(taskId)-\(services.idGenerator.newID())",
                                                content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        case Self.rescheduleActionId:
            // Reschedule from the lock screen: push the task's due to tomorrow 9am (a real mutation that
            // syncs + re-arms reminders), so a not-now reminder doesn't need the app to be opened.
            let ctx = container.mainContext
            var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == taskId })
            descriptor.fetchLimit = 1
            guard let task = try? ctx.fetch(descriptor).first else { return }
            let cal = Calendar.current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: services.clock.now()) ?? services.clock.now()
            let at = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
            let mutation = TaskMutation(context: ctx, engine: services.syncEngine,
                                        clock: services.clock, idGenerator: services.idGenerator)
            await mutation.reschedule(task, dueAt: at)
            if AppConfig.isLiveSync { await services.syncOnce() }
        default:
            break // default tap (open app) — no deep-link target yet
        }
    }
}
