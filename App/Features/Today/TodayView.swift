import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// The Today tab — the app's home base (AppSpec §4). Phase 0 is a deliberately thin slice: it lists
/// the user's tasks from SwiftData and offers a `+` button that creates one offline and enqueues it
/// for sync. The sectograph hero, agenda (now→next), routine progress, and morning brief arrive in
/// later phases (AppSpec §5.3, DevelopmentPlan Phase 1–2).
///
/// Requires the Xcode app target (SwiftUI + SwiftData). Will not build via `swift build` standalone.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services

    /// Live query: non-deleted tasks, newest first. SwiftData keeps this in sync with the store.
    @Query(
        filter: #Predicate<TaskModel> { $0.deletedAt == nil },
        sort: \TaskModel.createdAt,
        order: .reverse
    )
    private var tasks: [TaskModel]

    /// Non-deleted lists, so each task row can show its list as a chip once it syncs from the server
    /// (proves `list` entities now round-trip into SwiftData — DevelopmentPlan P1-D/F).
    @Query(filter: #Predicate<TaskListModel> { $0.deletedAt == nil })
    private var lists: [TaskListModel]

    @State private var isCreating = false
    @State private var newTitle = ""
    /// The task whose detail sheet is open (P1-E).
    @State private var selectedTask: TaskModel?

    var body: some View {
        NavigationStack {
            Group {
                if tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newTitle = ""
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add task")
                }
            }
            .alert("New Task", isPresented: $isCreating) {
                TextField("Title", text: $newTitle)
                Button("Add") { Task { await addTask() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Create a task. It's saved offline and synced when you're online.")
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
                    .environment(auth)
                    .environment(services)
            }
        }
    }

    private var taskList: some View {
        List {
            ForEach(tasks) { task in
                TaskRow(
                    title: task.title,
                    isDone: task.status == .done,
                    priorityLevel: task.priority.rawValue,
                    list: list(for: task).map {
                        TaskRow.ListBadge(name: $0.name, systemImage: $0.icon, colorHex: $0.colorHex)
                    },
                    dueText: dueText(for: task),
                    isPendingSync: task.syncState != .synced,
                    onToggle: { Task { await toggleComplete(task) } }
                )
                .contentShape(Rectangle())
                .onTapGesture { selectedTask = task }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { Task { await delete(task) } } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { Task { await toggleComplete(task) } } label: {
                        Label(task.status == .done ? "Reopen" : "Done",
                              systemImage: task.status == .done ? "arrow.uturn.left" : "checkmark.circle")
                    }
                    .tint(task.status == .done ? .gray : .green)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No tasks yet", systemImage: "checklist")
        } description: {
            Text("Tap + to capture your first task.")
        }
    }

    private func addTask() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        // Owner id from the signed-in session; fall back to a local placeholder before sign-in so
        // the skeleton is usable in the simulator without a backend.
        let ownerId: String
        if case let .signedIn(userId) = auth.state, let userId { ownerId = userId }
        else { ownerId = "local-user" }

        let creator = TaskCreation(
            context: modelContext,
            engine: services.syncEngine,
            ownerId: ownerId,
            clock: services.clock,
            idGenerator: services.idGenerator
        )
        await creator.createTask(title: title)
        // Flush the new task to the server when live-syncing (DevelopmentPlan P1-D).
        if AppConfig.isLiveSync { await services.syncOnce() }
    }

    /// Resolve a task's parent list (if assigned + already synced locally) for the row chip.
    private func list(for task: TaskModel) -> TaskListModel? {
        guard let listId = task.listId else { return nil }
        return lists.first { $0.id == listId }
    }

    // MARK: - Mutations (P1-E)

    private var mutation: TaskMutation {
        TaskMutation(context: modelContext, engine: services.syncEngine,
                     clock: services.clock, idGenerator: services.idGenerator)
    }

    private func toggleComplete(_ task: TaskModel) async {
        await mutation.toggleComplete(task)
        if AppConfig.isLiveSync { await services.syncOnce() }
    }

    private func delete(_ task: TaskModel) async {
        await mutation.delete(task)
        if AppConfig.isLiveSync { await services.syncOnce() }
    }

    private func dueText(for task: TaskModel) -> String? {
        guard let due = task.dueAt else { return nil }
        return due.formatted(date: .abbreviated, time: .shortened)
    }
}
