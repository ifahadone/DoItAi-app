import Foundation

/// A read-only calendar event (from EventKit) reduced to what the free/busy overlay needs
/// (DevelopmentPlan P2-5). Times are epoch seconds so the mapper is pure (no `Date` construction).
/// Lives in DesignSystem because it maps to ``SectographItem`` (the dial/grid block model).
public struct CalendarEvent: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var startEpoch: Double
    public var endEpoch: Double
    public var isAllDay: Bool

    public init(id: String, title: String, startEpoch: Double, endEpoch: Double, isAllDay: Bool = false) {
        self.id = id
        self.title = title
        self.startEpoch = startEpoch
        self.endEpoch = endEpoch
        self.isAllDay = isAllDay
    }
}

/// Maps calendar events to dial/grid "busy" blocks for a given day. Pure: the caller supplies the
/// day's start (epoch seconds), so the portion of each event intersecting today is clamped to 0…1440
/// minutes. All-day events are skipped (they'd fill the whole dial).
public enum CalendarBusyMapper {
    public static func busyItems(
        from events: [CalendarEvent],
        dayStartEpoch: Double,
        colorHex: String? = nil
    ) -> [SectographItem] {
        let dayEnd = dayStartEpoch + 86_400
        return events.compactMap { event in
            guard !event.isAllDay else { return nil }
            let start = max(event.startEpoch, dayStartEpoch)
            let end = min(event.endEpoch, dayEnd)
            guard end > start else { return nil }
            let startMinute = Int((start - dayStartEpoch) / 60)
            let endMinute = min(1440, Int((end - dayStartEpoch) / 60))
            guard endMinute > startMinute else { return nil }
            return SectographItem(id: "busy:\(event.id)", startMinute: startMinute, endMinute: endMinute, colorHex: colorHex)
        }
    }
}
