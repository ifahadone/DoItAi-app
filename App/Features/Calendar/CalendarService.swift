import Foundation
import EventKit
import DesignSystem

/// Reads the user's calendar (free/busy) for the dial + planner overlay (AppSpec §5.5, P2-5).
///
/// EventKit access needs the user's permission — a system prompt, so granting it is a device step;
/// without it, the fetch returns nothing and the overlay is simply empty. Read-only here; calendar
/// **write-back** is Phase 3. The app's Info.plist must carry `NSCalendarsFullAccessUsageDescription`.
@MainActor
final class CalendarService {
    private let store = EKEventStore()

    @discardableResult
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Today's events as ``DesignSystem/CalendarEvent``s (empty unless authorized).
    func todayEvents(now: Date) -> [CalendarEvent] {
        guard isAuthorized else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Busy",
                startEpoch: event.startDate.timeIntervalSince1970,
                endEpoch: event.endDate.timeIntervalSince1970,
                isAllDay: event.isAllDay
            )
        }
    }

    /// Today's events mapped to dial/grid busy blocks (empty unless authorized).
    func busyItems(now: Date) -> [SectographItem] {
        let dayStart = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        return CalendarBusyMapper.busyItems(from: todayEvents(now: now), dayStartEpoch: dayStart)
    }
}
