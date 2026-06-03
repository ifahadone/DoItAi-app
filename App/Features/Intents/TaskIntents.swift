import AppIntents
import SwiftData
import Foundation

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
