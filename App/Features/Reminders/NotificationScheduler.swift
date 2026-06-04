import Foundation
import UserNotifications
import SyncCore

/// Schedules local notifications for reminders (DevelopmentPlan P1-I). Honors iOS's 64-pending cap by
/// re-arming a rolling window (which 64 to schedule is decided by ``SyncCore/NotificationPlanner``).
///
/// Delivery needs notification authorization (request it from onboarding) + a real device; the
/// *scheduling* itself (pending requests) works in the simulator, which is how P1-I is verified.
@MainActor
struct NotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    /// Namespace reminder requests so re-arming reminders never clobbers alarm requests (which carry
    /// the `alarm-` prefix; see ``AlarmScheduler``). Both schedulers share the 64-slot pending pool.
    private let identifierPrefix = "reminder-"

    /// Request alert/sound/badge + Time-Sensitive authorization (the latter so alarm chains can break
    /// through Focus, P3-6). Best-effort, idempotent — after the first determination iOS returns the
    /// existing status without re-prompting. Returns whether granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])) ?? false
    }

    /// Re-arm the rolling window: clear our previously-scheduled *reminders* (by prefix, leaving alarms
    /// intact), then schedule the planned set as calendar-triggered notifications keyed by reminder id.
    @discardableResult
    func rearm(_ planned: [PlannedNotification]) async -> Int {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix(identifierPrefix) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ours)
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        var scheduled = 0
        var firstError: String?
        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title.isEmpty ? "Reminder" : item.title
            content.sound = .default
            let dateComponents = Calendar.current.dateComponents(components, from: item.fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: identifierPrefix + item.reminderId, content: content, trigger: trigger)
            do { try await center.add(request); scheduled += 1 }
            catch { if firstError == nil { firstError = "\(error)" } }
        }
        #if DEBUG
        if let firstError { print("NotificationScheduler: planned=\(planned.count) scheduled=\(scheduled) firstError=\(firstError)") }
        #endif
        return scheduled
    }

    /// How many reminder notifications are currently scheduled (≤ 64). Used to verify the re-arm.
    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(identifierPrefix) }.count
    }
}
