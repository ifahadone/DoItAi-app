import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// The day planner (AppSpec §5.3, DevelopmentPlan P2-3). A vertical time grid of today's blocks
/// (lane-packed for overlaps by ``DayGridView``). Tap empty space to create a 1-hour block; drag a
/// block to move it; drag its bottom handle to resize. Each gesture flows through ``TaskMutation``
/// (`setSchedule`) and syncs.
struct DayPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil })
    private var tasks: [TaskModel]
    @Query(filter: #Predicate<TaskListModel> { $0.deletedAt == nil })
    private var lists: [TaskListModel]

    @State private var selectedTask: TaskModel?

    var body: some View {
        DayGridView(
            items: items,
            titles: Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }),
            onCreate: { minute in Task { await createBlock(at: minute) } },
            onMove: { id, start in Task { await move(id, toStart: start) } },
            onResize: { id, end in Task { await resize(id, toEnd: end) } },
            onTap: { id in selectedTask = tasks.first { $0.id == id } }
        )
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task).environment(auth).environment(services)
        }
    }

    // MARK: - Data

    /// Today's blocks: scheduled ranges as real blocks; due-only tasks as 30-minute blocks at due time.
    private var items: [SectographItem] {
        let calendar = Calendar.current
        let now = services.clock.now()
        func minute(_ date: Date) -> Int? {
            guard calendar.isDate(date, inSameDayAs: now) else { return nil }
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        return tasks.compactMap { task in
            let color = task.listId.flatMap { id in lists.first { $0.id == id }?.colorHex }
            if let start = task.scheduledStart, let startMinute = minute(start) {
                let endMinute = task.scheduledEnd.flatMap(minute) ?? min(1440, startMinute + 60)
                return SectographItem(id: task.id, startMinute: startMinute, endMinute: endMinute, colorHex: color)
            } else if let due = task.dueAt, let dueMinute = minute(due) {
                return SectographItem(id: task.id, startMinute: dueMinute, endMinute: min(1440, dueMinute + 30), colorHex: color)
            }
            return nil
        }
    }

    // MARK: - Mutations

    private var mutation: TaskMutation {
        TaskMutation(context: modelContext, engine: services.syncEngine,
                     clock: services.clock, idGenerator: services.idGenerator)
    }

    private func date(atMinute minute: Int) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: services.clock.now())
        return calendar.date(byAdding: .minute, value: max(0, min(1440, minute)), to: startOfDay) ?? startOfDay
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func durationMinutes(_ task: TaskModel) -> Int {
        if let s = task.scheduledStart, let e = task.scheduledEnd {
            return max(15, Int(e.timeIntervalSince(s) / 60))
        }
        return 60
    }

    private func createBlock(at minute: Int) async {
        let creator = TaskCreation(context: modelContext, engine: services.syncEngine,
                                   ownerId: ownerId, clock: services.clock, idGenerator: services.idGenerator)
        let id = await creator.createTask(title: "New block")
        if let task = tasks.first(where: { $0.id == id }) ?? fetch(id) {
            await mutation.setSchedule(task, start: date(atMinute: minute), end: date(atMinute: min(1440, minute + 60)))
        }
        await syncIfLive()
    }

    private func move(_ id: String, toStart startMinute: Int) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let dur = durationMinutes(task)
        await mutation.setSchedule(task, start: date(atMinute: startMinute),
                                   end: date(atMinute: min(1440, startMinute + dur)))
        await syncIfLive()
    }

    private func resize(_ id: String, toEnd endMinute: Int) async {
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        let startMinute = task.scheduledStart.map(minuteOfDay) ?? max(0, endMinute - 60)
        await mutation.setSchedule(task, start: date(atMinute: startMinute),
                                   end: date(atMinute: max(startMinute + 15, endMinute)))
        await syncIfLive()
    }

    private func fetch(_ id: String) -> TaskModel? {
        var d = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try? modelContext.fetch(d).first
    }

    private var ownerId: String {
        if case let .signedIn(userId) = auth.state, let userId { return userId }
        return "local-user"
    }
    private func syncIfLive() async { if AppConfig.isLiveSync { await services.syncOnce() } }
}
