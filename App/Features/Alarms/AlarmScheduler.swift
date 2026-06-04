import Foundation
import UserNotifications
import SyncCore

/// Schedules alarm delivery via local notifications (AppSpec §5.6, DevelopmentPlan P3-6).
///
/// **iOS reality (honest onboarding).** Third-party apps cannot schedule a true system alarm that
/// overrides silent mode / Focus the way the Clock app does. We use **Time-Sensitive** notifications
/// (entitlement-free; break through Focus when the user allows it) with a custom sound and an optional
/// Live Activity for lock-screen visibility. A louder **Critical** alert needs Apple's Critical-alerts
/// entitlement (a review). Delivery also needs notification authorization + a real device — the
/// *scheduling* (pending requests) works in the simulator, which is how this is verified.
@MainActor
struct AlarmScheduler {
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "alarm-"

    static let onboardingNote =
        "iOS limits third-party alarms. Time-Sensitive notifications break through Focus when you allow "
        + "them; a louder Critical alert requires a special Apple entitlement. Keep DoIT notifications on "
        + "and set 'Time Sensitive' allowed for reliable wake-ups."

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])) ?? false
    }

    /// Re-arm the alarm window: clear our scheduled alarms, then schedule the planned (soonest ≤64) set
    /// as Time-Sensitive calendar notifications. Returns the count scheduled.
    @discardableResult
    func rearm(_ planned: [PlannedNotification]) async -> Int {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix(identifierPrefix) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        var scheduled = 0
        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title.isEmpty ? "Alarm" : item.title
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            let dateComponents = Calendar.current.dateComponents(components, from: item.fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: identifierPrefix + item.reminderId, content: content, trigger: trigger)
            if (try? await center.add(request)) != nil { scheduled += 1 }
        }
        return scheduled
    }

    func pendingAlarmCount() async -> Int {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(identifierPrefix) }.count
    }
}
