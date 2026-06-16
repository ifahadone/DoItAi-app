import AppIntents
import SwiftData
import Foundation
import SyncCore

/// App Intents for interactive task/reminder actions from outside the app — Shortcuts, Siri, and the
/// agenda widget's buttons (AppSpec §5.9, DevelopmentPlan P1-J). They mutate the shared SwiftData
/// store directly; the change is picked up + flushed on the app's next foreground sync.
///
/// NOTE: full background sync of widget-driven edits needs the outbox persisted in the shared store
/// (today it's in-memory in `AppServices`), so an edit made while the app is suspended flushes on the
/// next launch. Tracked as a Phase-1 follow-up.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Mark a DoIT task done (or reopen it).")

    @Parameter(title: "Task ID")
    var taskId: String

    init() {}
    init(taskId: String) { self.taskId = taskId }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = PersistenceContainer.makeShared().mainContext
        var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == taskId })
        descriptor.fetchLimit = 1
        if let task = try context.fetch(descriptor).first {
            let nowDone = task.status != .done
            task.status = nowDone ? .done : .inbox
            task.completedAt = nowDone ? Date() : nil
            task.updatedAt = Date()
            if task.syncState == .synced { task.syncState = .pendingUpdate }
            try context.save()
        }
        return .result()
    }
}

/// Push a reminder's fire time forward by a fixed snooze interval.
struct SnoozeReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze Reminder"
    static var description = IntentDescription("Snooze a DoIT reminder.")

    @Parameter(title: "Reminder ID")
    var reminderId: String
    @Parameter(title: "Minutes", default: 15)
    var minutes: Int

    init() {}
    init(reminderId: String, minutes: Int = 15) {
        self.reminderId = reminderId
        self.minutes = minutes
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = PersistenceContainer.makeShared().mainContext
        var descriptor = FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == reminderId })
        descriptor.fetchLimit = 1
        if let reminder = try context.fetch(descriptor).first {
            let base = reminder.fireAt ?? Date()
            reminder.fireAt = max(base, Date()).addingTimeInterval(Double(minutes) * 60)
            reminder.updatedAt = Date()
            if reminder.syncState == .synced { reminder.syncState = .pendingUpdate }
            try context.save()
        }
        return .result()
    }
}

/// Capture a task from a natural-language phrase via Siri / Shortcuts (FR-QADD-100). Parses the phrase
/// with the on-device ``QuickAddParser`` (title + due date + priority + estimated duration) and inserts
/// a `pendingCreate` task into the shared store; it flushes on the app's next foreground sync (same
/// model + caveat as the other intents above).
struct QuickAddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Task"
    static var description = IntentDescription("Capture a task in DoIT from a natural-language phrase.")

    @Parameter(title: "Task", requestValueDialog: "What would you like to add?")
    var phrase: String

    init() {}
    init(phrase: String) { self.phrase = phrase }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parsed = QuickAddParser.parse(phrase)
        let title = parsed.title.isEmpty ? phrase : parsed.title
        let context = PersistenceContainer.makeShared().mainContext
        // Reuse an existing row's owner so the task belongs to the signed-in user; fall back to the
        // same local placeholder the in-app path uses pre-sign-in (the server re-derives the
        // authoritative owner from the auth token on push).
        var ownerDescriptor = FetchDescriptor<TaskModel>()
        ownerDescriptor.fetchLimit = 1
        let owner = (try? context.fetch(ownerDescriptor))?.first?.ownerId ?? "local-user"
        let now = Date()
        let task = TaskModel(
            id: UUID().uuidString, ownerId: owner, title: title,
            statusRaw: TaskStatus.inbox.rawValue, createdAt: now, updatedAt: now,
            serverVersion: 0, syncStateRaw: LocalSyncState.pendingCreate.rawValue)
        task.dueAt = parsed.dueAt
        task.priority = parsed.priority
        task.estimatedMinutes = parsed.estimatedMinutes
        context.insert(task)
        try context.save()
        return .result(dialog: "Added “\(title)” to DoIT.")
    }
}

/// Registers DoIT's App Intents as Siri-invocable shortcuts (FR-QADD-100).
struct DoITAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddTaskIntent(),
            phrases: [
                "Quick add in \(.applicationName)",
                "Add a task in \(.applicationName)",
                "Capture in \(.applicationName)",
            ],
            shortTitle: "Quick Add",
            systemImageName: "plus.circle.fill"
        )
    }
}
