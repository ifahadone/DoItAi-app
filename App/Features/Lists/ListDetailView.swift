import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Tasks belonging to one list (DevelopmentPlan P1-F "filter by list"). Add a task here and it's
/// created already assigned to the list. Tapping a row opens the shared ``TaskDetailView``.
struct ListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services
    @Bindable var list: TaskListModel

    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil },
           sort: \TaskModel.createdAt, order: .reverse)
    private var allTasks: [TaskModel]

    @State private var selectedTask: TaskModel?
    @State private var isCreating = false
    @State private var newTitle = ""
    @State private var showSharing = false
    @State private var showPaywall = false

    private var tasksInList: [TaskModel] { allTasks.filter { $0.listId == list.id } }

    var body: some View {
        List {
            if tasksInList.isEmpty {
                Text("No tasks in this list yet — tap + to add one.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(tasksInList) { task in
                TaskRow(
                    title: task.title,
                    isDone: task.status == .done,
                    priorityLevel: task.priority.rawValue,
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
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { newTitle = ""; isCreating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add task to list")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Sharing is a Pro feature (AppSpec §17); non-Pro taps land on the paywall.
                    if services.entitlements.isPro { showSharing = true } else { showPaywall = true }
                } label: { Image(systemName: "person.crop.circle.badge.plus") }
                    .accessibilityLabel("Share list")
            }
        }
        .alert("New Task", isPresented: $isCreating) {
            TextField("Title", text: $newTitle)
            Button("Add") { Task { await addTask() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Added to \(list.name).")
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task).environment(auth).environment(services)
        }
        .sheet(isPresented: $showSharing) {
            SharingView(list: list).environment(services)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environment(services)
        }
    }

    private var ownerId: String {
        if case let .signedIn(userId) = auth.state, let userId { return userId }
        return "local-user"
    }
    private var mutation: TaskMutation {
        TaskMutation(context: modelContext, engine: services.syncEngine,
                     clock: services.clock, idGenerator: services.idGenerator)
    }

    private func toggle(_ task: TaskModel) async { await mutation.toggleComplete(task); await syncIfLive() }
    private func delete(_ task: TaskModel) async { await mutation.delete(task); await syncIfLive() }

    private func addTask() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let creator = TaskCreation(context: modelContext, engine: services.syncEngine,
                                   ownerId: ownerId, clock: services.clock, idGenerator: services.idGenerator)
        await creator.createTask(title: title, listId: list.id)
        await syncIfLive()
    }

    private func syncIfLive() async { if AppConfig.isLiveSync { await services.syncOnce() } }
}
