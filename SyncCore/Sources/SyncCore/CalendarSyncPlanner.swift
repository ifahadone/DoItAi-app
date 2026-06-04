import Foundation

/// A DoIT scheduled block to mirror into the user's Apple Calendar (AppSpec §5.5 write-back, P3-7).
public struct CalendarExportBlock: Equatable, Sendable, Identifiable {
    public var taskId: String
    public var title: String
    public var startEpoch: Double
    public var endEpoch: Double

    public var id: String { taskId }

    public init(taskId: String, title: String, startEpoch: Double, endEpoch: Double) {
        self.taskId = taskId
        self.title = title
        self.startEpoch = startEpoch
        self.endEpoch = endEpoch
    }

    /// Stable fingerprint of the user-visible fields. The plan only emits an update when this changes,
    /// so unchanged blocks don't churn the calendar on every sync.
    public var contentHash: String { "\(title)|\(startEpoch)|\(endEpoch)" }
}

/// A previously-exported block: the DoIT task, the EKEvent it created, and the content it was exported
/// with (so we can detect drift). Persisted app-side keyed by `taskId`.
public struct ExportedEventRef: Equatable, Sendable {
    public var taskId: String
    public var eventId: String
    public var contentHash: String

    public init(taskId: String, eventId: String, contentHash: String) {
        self.taskId = taskId
        self.eventId = eventId
        self.contentHash = contentHash
    }
}

/// One event needing its fields refreshed (the DoIT block changed since last export).
public struct CalendarUpdate: Equatable, Sendable {
    public var block: CalendarExportBlock
    public var eventId: String

    public init(block: CalendarExportBlock, eventId: String) {
        self.block = block
        self.eventId = eventId
    }
}

/// The diff to reconcile DoIT's scheduled blocks with the calendar.
public struct CalendarSyncPlan: Equatable, Sendable {
    public var creates: [CalendarExportBlock]
    public var updates: [CalendarUpdate]
    public var deletes: [String] // EKEvent identifiers to remove

    public init(creates: [CalendarExportBlock] = [], updates: [CalendarUpdate] = [], deletes: [String] = []) {
        self.creates = creates
        self.updates = updates
        self.deletes = deletes
    }

    public var isEmpty: Bool { creates.isEmpty && updates.isEmpty && deletes.isEmpty }
}

/// Pure planner for calendar write-back (P3-7). Given the current set of DoIT blocks and the events we
/// exported last time, computes the minimal create/update/delete set. Idempotent: re-running with the
/// same inputs after applying yields an empty plan. The EventKit calls themselves (create/save/remove)
/// are device-bound and live in the app's `CalendarWriteBackService`.
public enum CalendarSyncPlanner {
    public static func plan(blocks: [CalendarExportBlock], existing: [ExportedEventRef]) -> CalendarSyncPlan {
        let refByTask = Dictionary(existing.map { ($0.taskId, $0) }, uniquingKeysWith: { first, _ in first })
        let blockTaskIds = Set(blocks.map(\.taskId))

        var creates: [CalendarExportBlock] = []
        var updates: [CalendarUpdate] = []
        for block in blocks {
            if let ref = refByTask[block.taskId] {
                if ref.contentHash != block.contentHash {
                    updates.append(CalendarUpdate(block: block, eventId: ref.eventId))
                }
            } else {
                creates.append(block)
            }
        }
        // Anything we exported before but is no longer a scheduled block → remove from the calendar.
        let deletes = existing.filter { !blockTaskIds.contains($0.taskId) }.map(\.eventId)
        return CalendarSyncPlan(creates: creates, updates: updates, deletes: deletes)
    }
}
