import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// The Plan tab — the built-in smart lists (AppSpec §5.4, DevelopmentPlan P1-G). Each row shows a
/// smart list with its active-task count; drilling in lists those tasks. Membership comes from the
/// shared ``SmartListClassifier`` (same logic the golden-fixture test pins), applied in-memory over
/// the SwiftData rows.
struct SmartListsView: View {
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil })
    private var tasks: [TaskModel]

    var body: some View {
        NavigationStack {
            List {
                ForEach(SmartList.allCases) { smart in
                    NavigationLink {
                        SmartListDetailView(smartList: smart)
                    } label: {
                        HStack {
                            Label(smart.title, systemImage: smart.systemImage)
                            Spacer()
                            Text("\(count(smart))").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Plan")
        }
    }

    private func count(_ smart: SmartList) -> Int {
        let now = services.clock.now()
        return tasks.filter {
            SmartListClassifier.classify(status: $0.status, dueAt: $0.dueAt,
                                         scheduledStart: $0.scheduledStart, now: now) == smart
        }.count
    }
}

/// The tasks belonging to one smart list (filtered via the classifier). Reuses ``TaskRow`` +
/// ``TaskDetailView`` and the same complete/delete mutations as Today.
struct SmartListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services
    let smartList: SmartList

    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil }, sort: \TaskModel.dueAt)
    private var allTasks: [TaskModel]

    @State private var selectedTask: TaskModel?

    private var tasks: [TaskModel] {
        let now = services.clock.now()
        return allTasks.filter {
            SmartListClassifier.classify(status: $0.status, dueAt: $0.dueAt,
                                         scheduledStart: $0.scheduledStart, now: now) == smartList
        }
    }

    var body: some View {
        List {
            if tasks.isEmpty {
                Text("Nothing in \(smartList.title).").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(tasks) { task in
                TaskRow(
                    title: task.title,
                    isDone: task.status == .done,
                    priorityLevel: task.priority.rawValue,
                    dueText: dueText(task),
                    isPendingSync: task.syncState != .synced,
                    onToggle: { Task { await toggle(task) } }
                )
                .contentShape(Rectangle())
                .onTapGesture { selectedTask = task }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { Task { await delete(task) } } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(smartList.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task).environment(auth).environment(services)
        }
    }

    private var mutation: TaskMutation {
        TaskMutation(context: modelContext, engine: services.syncEngine,
                     clock: services.clock, idGenerator: services.idGenerator)
    }
    private func toggle(_ task: TaskModel) async { await mutation.toggleComplete(task); await syncIfLive() }
    private func delete(_ task: TaskModel) async { await mutation.delete(task); await syncIfLive() }
    private func dueText(_ task: TaskModel) -> String? {
        task.dueAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
    }
    private func syncIfLive() async { if AppConfig.isLiveSync { await services.syncOnce() } }
}
