import Foundation
import EventKit
import CoreGraphics
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

    /// All event calendars available on the device — for the free/busy selection screen (G05-S09).
    func availableCalendars() -> [CalendarInfo] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, colorHex: Self.hex($0.cgColor)) }
    }

    /// Calendar identifiers the user chose to include in free/busy. Empty = all calendars (the default).
    var selectedCalendarIdentifiers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.selectedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.selectedKey) }
    }
    private static let selectedKey = "doit.calendar.selectedIDs"

    /// The EKCalendars matching the user's selection, or `nil` (= all) when nothing is selected.
    private func effectiveCalendars() -> [EKCalendar]? {
        let ids = selectedCalendarIdentifiers
        guard !ids.isEmpty else { return nil }
        let chosen = store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
        return chosen.isEmpty ? nil : chosen
    }

    private static func hex(_ cg: CGColor?) -> String? {
        guard let cg, let comps = cg.components, comps.count >= 3 else { return nil }
        let r = Int((comps[0] * 255).rounded()), g = Int((comps[1] * 255).rounded()), b = Int((comps[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }

    /// Today's events as ``DesignSystem/CalendarEvent``s (empty unless authorized).
    func todayEvents(now: Date) -> [CalendarEvent] {
        guard isAuthorized else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: effectiveCalendars())
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

/// A calendar the user can include/exclude from DoIT's free/busy overlay (journey G05-S09).
struct CalendarInfo: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let colorHex: String?
}
