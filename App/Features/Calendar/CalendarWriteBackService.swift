import Foundation
import EventKit
import SyncCore

/// Mirrors DoIT scheduled blocks into the user's Apple Calendar (AppSpec §5.5 write-back, P3-7).
///
/// **Device-bound.** Needs calendar write permission (a system prompt). The diff itself — which events
/// to create / update / delete — is computed by the pure, tested ``SyncCore/CalendarSyncPlanner``, so
/// re-running after applying is a no-op (idempotent). EKEvent identifiers are device-local (they don't
/// sync), so the task→event mapping is persisted locally in `UserDefaults`, keyed by owner.
@MainActor
final class CalendarWriteBackService {
    private let store = EKEventStore()
    private let defaults: UserDefaults
    private let exportKeyPrefix = "doit.calendarExport."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Full access (write-back needs to read events back by identifier to update/delete them).
    @discardableResult
    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Apply the create/update/delete diff for `blocks`. Returns the applied counts. No-op (returns
    /// zeros) without authorization, so it's safe to call on every sync.
    @discardableResult
    func writeBack(blocks: [CalendarExportBlock], ownerId: String) async -> (created: Int, updated: Int, deleted: Int) {
        guard isAuthorized, let calendar = store.defaultCalendarForNewEvents else { return (0, 0, 0) }
        var refs = loadRefs(ownerId: ownerId)
        let plan = CalendarSyncPlanner.plan(blocks: blocks, existing: Array(refs.values))

        var created = 0, updated = 0, deleted = 0
        for block in plan.creates {
            let event = EKEvent(eventStore: store)
            apply(block, to: event, calendar: calendar)
            if (try? store.save(event, span: .thisEvent)) != nil, let eid = event.eventIdentifier {
                refs[block.taskId] = ExportedEventRef(taskId: block.taskId, eventId: eid, contentHash: block.contentHash)
                created += 1
            }
        }
        for update in plan.updates {
            guard let event = store.event(withIdentifier: update.eventId) else { continue }
            apply(update.block, to: event, calendar: calendar)
            if (try? store.save(event, span: .thisEvent)) != nil {
                refs[update.block.taskId] = ExportedEventRef(taskId: update.block.taskId, eventId: update.eventId, contentHash: update.block.contentHash)
                updated += 1
            }
        }
        for eid in plan.deletes {
            if let event = store.event(withIdentifier: eid), (try? store.remove(event, span: .thisEvent)) != nil {
                deleted += 1
            }
            refs = refs.filter { $0.value.eventId != eid }
        }
        saveRefs(refs, ownerId: ownerId)
        return (created, updated, deleted)
    }

    private func apply(_ block: CalendarExportBlock, to event: EKEvent, calendar: EKCalendar) {
        event.title = block.title
        event.startDate = Date(timeIntervalSince1970: block.startEpoch)
        event.endDate = Date(timeIntervalSince1970: block.endEpoch)
        event.calendar = calendar
        event.notes = "Scheduled by DoIT"
    }

    // MARK: - local ref persistence (EKEvent identifiers are device-local, not synced)

    private struct StoredRef: Codable { var taskId: String; var eventId: String; var contentHash: String }

    private func key(_ ownerId: String) -> String { exportKeyPrefix + ownerId }

    private func loadRefs(ownerId: String) -> [String: ExportedEventRef] {
        guard let data = defaults.data(forKey: key(ownerId)),
              let decoded = try? JSONDecoder().decode([String: StoredRef].self, from: data) else { return [:] }
        return decoded.mapValues { ExportedEventRef(taskId: $0.taskId, eventId: $0.eventId, contentHash: $0.contentHash) }
    }

    private func saveRefs(_ refs: [String: ExportedEventRef], ownerId: String) {
        let stored = refs.mapValues { StoredRef(taskId: $0.taskId, eventId: $0.eventId, contentHash: $0.contentHash) }
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: key(ownerId)) }
    }
}
