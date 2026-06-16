import Foundation

/// One agenda item considered for the Today "now → next" card (FR-TODAY-110). A scheduled item has
/// `start`/`end`; a due-only item carries `due`.
public struct AgendaSlotItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date?
    public var end: Date?
    public var due: Date?

    public init(id: String, title: String, start: Date? = nil, end: Date? = nil, due: Date? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.due = due
    }

    /// The time this item is anchored to for "next" ordering: its scheduled start, else its due time.
    public var anchor: Date? { start ?? due }
}

/// Selects the block happening *now* and the soonest item *next*, for the Today agenda card. Pure +
/// deterministic (injected `now`) so it is unit-tested.
public enum NextUpPlanner {
    public struct Result: Sendable, Equatable {
        /// A scheduled block whose interval contains `now`, if any.
        public var current: AgendaSlotItem?
        /// The soonest item whose anchor is strictly after `now` (excluding `current`).
        public var next: AgendaSlotItem?

        public init(current: AgendaSlotItem? = nil, next: AgendaSlotItem? = nil) {
            self.current = current
            self.next = next
        }
    }

    public static func compute(_ items: [AgendaSlotItem], now: Date) -> Result {
        let current = items.first { item in
            guard let s = item.start, let e = item.end else { return false }
            return s <= now && now < e
        }
        let next = items
            .filter { $0.id != current?.id }
            .compactMap { item -> (Date, AgendaSlotItem)? in
                guard let a = item.anchor, a > now else { return nil }
                return (a, item)
            }
            .min(by: { $0.0 < $1.0 })?
            .1
        return Result(current: current, next: next)
    }

    /// Whole minutes remaining in `item`'s block from `now` (>= 0), or nil if it isn't a current block.
    public static func minutesLeft(in item: AgendaSlotItem, now: Date) -> Int? {
        guard let e = item.end else { return nil }
        return max(0, Int(e.timeIntervalSince(now) / 60))
    }
}
