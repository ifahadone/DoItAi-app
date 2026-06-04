#if DEBUG
import Foundation
import SwiftData
import SyncCore

/// DEBUG-only sample data for the `-uiDemo` launch mode (see ``AppConfig/isUIDemo``).
///
/// Seeds a handful of ``TaskModel`` rows into an empty store so the Today shell is demoable in the
/// simulator without a backend or a completed Sign in with Apple flow. This file is wrapped in
/// `#if DEBUG`, so none of it is ever compiled into a release build.
enum DemoData {
    @MainActor
    static func seed(into container: ModelContainer) {
        let context = container.mainContext

        // Only seed an empty store, so repeated launches don't pile up duplicates.
        let existing = (try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0
        guard existing == 0 else { return }

        let now = Date()
        let owner = "demo-user"
        let cal = Calendar.current
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        }

        // Lists give the dial's arcs their colors + SF Symbols.
        let listSpecs: [(name: String, colorHex: String, icon: String)] = [
            ("Work", "#2E7DF6", "briefcase.fill"),
            ("Health", "#34C759", "heart.fill"),
            ("Personal", "#FF9F0A", "house.fill"),
        ]
        var listId: [String: String] = [:]
        for (index, spec) in listSpecs.enumerated() {
            let id = UUID().uuidString
            listId[spec.name] = id
            context.insert(TaskListModel(
                id: id, ownerId: owner, name: spec.name, colorHex: spec.colorHex, icon: spec.icon,
                sortIndex: index, createdAt: now, updatedAt: now, serverVersion: 1,
                syncStateRaw: LocalSyncState.synced.rawValue))
        }

        func makeTask(_ title: String, _ priority: Priority, _ status: TaskStatus,
                      list: String?, rank: Int, pending: Bool = false) -> TaskModel {
            let task = TaskModel(
                id: UUID().uuidString, ownerId: owner, title: title,
                statusRaw: status.rawValue, priorityRaw: priority.rawValue, rank: rank,
                createdAt: now.addingTimeInterval(Double(-rank) * 600), updatedAt: now,
                serverVersion: pending ? 0 : 1,
                syncStateRaw: (pending ? LocalSyncState.pendingCreate : .synced).rawValue)
            task.listId = list.flatMap { listId[$0] }
            return task
        }

        // A block spanning "now" → the emphasised (brighter/thicker, glowing) current arc.
        let nowBlock = makeTask("Focus: API design", .p1, .inProgress, list: "Work", rank: 0)
        nowBlock.scheduledStart = now.addingTimeInterval(-45 * 60)
        nowBlock.scheduledEnd = now.addingTimeInterval(45 * 60)
        context.insert(nowBlock)

        // Scheduled blocks → gradient arcs around the dial (one done → dimmed).
        let blocks: [(String, Priority, TaskStatus, String, Date, Date)] = [
            ("Deep work — API contract", .p2, .scheduled, "Work",   at(9, 0),  at(11, 0)),
            ("Morning run",              .p3, .done,      "Health", at(6, 30), at(7, 15)),
            ("Team sync",                .p2, .scheduled, "Work",   at(13, 0), at(13, 45)),
            ("Gym session",              .p3, .scheduled, "Health", at(18, 0), at(19, 0)),
        ]
        for (offset, b) in blocks.enumerated() {
            let task = makeTask(b.0, b.1, b.2, list: b.3, rank: offset + 1)
            task.scheduledStart = b.4
            task.scheduledEnd = b.5
            context.insert(task)
        }

        // Due-only task → a dashed instant marker + the list icon chip.
        let due = makeTask("Call the dentist", .p2, .scheduled, list: "Personal", rank: 5)
        due.dueAt = at(16, 0)
        context.insert(due)

        // One unscheduled, pending task to show the offline badge in the list.
        context.insert(makeTask("Buy groceries for the week", Priority.none, .inbox,
                                 list: "Personal", rank: 6, pending: true))

        try? context.save()
    }
}
#endif
