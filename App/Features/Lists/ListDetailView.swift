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

    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil && !$0.archived && $0.statusRaw != 4 },
           sort: \TaskModel.createdAt, order: .reverse)
    private var allTasks: [TaskModel]

    @State private var selectedTask: TaskModel?
    @State private var isCreating = false
    @State private var newTitle = ""
    @State private var query = ""
    @State private var showSharing = false
    @State private var showPaywall = false
    /// Contextual Pro gate for sharing (journey G03-S11 / G16): explains the feature before the full
    /// paywall. `upgradeAfterGate` defers presenting the paywall until this sheet fully dismisses.
    @State private var showProGate = false
    @State private var upgradeAfterGate = false
    /// Multi-select for bulk edit in edit mode (FR-TASK-170).
    @State private var selection = Set<String>()
    @Environment(\.editMode) private var editMode

    /// Tasks in this list, ordered by manual `rank` (then newest-first as a tiebreak) so drag-to-reorder
    /// sticks (FR-TASK-150).
    private var tasksInList: [TaskModel] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return allTasks
            .filter { $0.listId == list.id }
            .filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) || ($0.notes?.localizedCaseInsensitiveContains(q) ?? false) }
            .sorted { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return a.createdAt > b.createdAt
            }
    }

    var body: some View {
        List(selection: $selection) {
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
                .onTapGesture { if editMode?.wrappedValue.isEditing != true { selectedTask = task } }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { Task { await delete(task) } } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove(perform: move)
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search this list")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .primaryAction) {
                Button { newTitle = ""; isCreating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add task to list")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Sharing is a Pro feature (AppSpec §17); non-Pro taps see a contextual gate first.
                    if services.entitlements.isPro { showSharing = true } else { showProGate = true }
                } label: { Image(systemName: "person.crop.circle.badge.plus") }
                    .accessibilityLabel("Share list")
            }
            // Bulk-edit bar: appears in edit mode once rows are selected (FR-TASK-170).
            if editMode?.wrappedValue.isEditing == true && !selection.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { Task { await bulkComplete() } } label: { Label("Complete", systemImage: "checkmark.circle") }
                    Spacer()
                    Menu {
                        ForEach(ReschedulePreset.allCases.filter { $0.date(from: services.clock.now()) != nil }) { preset in
                            Button { Task { await bulkReschedule(preset) } } label: {
                                Label(preset.label, systemImage: preset.systemImage)
                            }
                        }
                    } label: { Label("Reschedule", systemImage: "calendar.badge.clock") }
                    Spacer()
                    Button { Task { await bulkArchive() } } label: { Label("Archive", systemImage: "archivebox") }
                    Spacer()
                    Button(role: .destructive) { Task { await bulkDelete() } } label: { Label("Delete", systemImage: "trash") }
                }
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
        .sheet(isPresented: $showProGate, onDismiss: {
            if upgradeAfterGate { upgradeAfterGate = false; showPaywall = true }
        }) {
            VStack {
                ProGateCard(
                    feature: "Sharing & collaboration",
                    message: "Share “\(list.name)”, assign tasks, and comment with your team. Available on DoIT Pro.",
                    onUpgrade: { upgradeAfterGate = true; showProGate = false },
                    fallbackTitle: "Not now", onFallback: { showProGate = false }
                )
                Spacer()
            }
            .padding()
            .presentationDetents([.medium])
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

    // MARK: - Bulk edit (FR-TASK-170)

    private var selectedTasks: [TaskModel] { tasksInList.filter { selection.contains($0.id) } }

    private func bulkComplete() async {
        for task in selectedTasks where task.status != .done { await mutation.toggleComplete(task) }
        selection.removeAll(); await syncIfLive()
    }
    private func bulkArchive() async {
        for task in selectedTasks { await mutation.setArchived(task, true) }
        selection.removeAll(); await syncIfLive()
    }
    private func bulkDelete() async {
        for task in selectedTasks { await mutation.delete(task) }
        selection.removeAll(); await syncIfLive()
    }
    private func bulkReschedule(_ preset: ReschedulePreset) async {
        guard let date = preset.date(from: services.clock.now()) else { return }
        for task in selectedTasks { await mutation.reschedule(task, dueAt: date) }
        selection.removeAll(); await syncIfLive()
    }

    /// Drag-to-reorder: reassign each task's `rank` to its new index (FR-TASK-150).
    private func move(from source: IndexSet, to destination: Int) {
        var ordered = tasksInList
        ordered.move(fromOffsets: source, toOffset: destination)
        Task {
            for (index, task) in ordered.enumerated() { await mutation.setRank(task, index) }
            await syncIfLive()
        }
    }

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
