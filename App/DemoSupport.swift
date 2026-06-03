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

        // (title, priority, status, pendingSync) — one left "pending" to show the offline badge.
        let samples: [(String, Priority, TaskStatus, Bool)] = [
            ("Draft the DoIT API contract",            .p1,           .inProgress, true),
            ("Plan the week in the sectograph",        .p2,           .scheduled,  false),
            ("Morning routine — meditate, gym, read",  .p3,           .inbox,      false),
            ("Buy groceries for the week",             Priority.none, .inbox,      false),
            ("Review pull requests",                   .p2,           .done,       false),
        ]

        for (index, sample) in samples.enumerated() {
            let (title, priority, status, pending) = sample
            let task = TaskModel(
                id: UUID().uuidString,
                ownerId: owner,
                title: title,
                statusRaw: status.rawValue,
                priorityRaw: priority.rawValue,
                rank: index,
                createdAt: now.addingTimeInterval(Double(-index) * 600),
                updatedAt: now,
                serverVersion: pending ? 0 : 1,
                syncStateRaw: (pending ? LocalSyncState.pendingCreate : .synced).rawValue
            )
            context.insert(task)
        }

        try? context.save()
    }
}
#endif
