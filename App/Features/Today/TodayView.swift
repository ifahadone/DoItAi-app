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

    /// Non-deleted tags, to render a task's tag pills (P1-F).
    @Query(filter: #Predicate<TagModel> { $0.deletedAt == nil })
    private var allTags: [TagModel]

    /// The user's chosen day-dial style (P5-5 sectograph variants), persisted across launches.
    @AppStorage("dialStyle") private var dialStyleRaw = DialStyle.arc.rawValue
    private var dialStyle: DialStyle { DialStyle(rawValue: dialStyleRaw) ?? .arc }

    @State private var isCreating = false
    @State private var newTitle = ""
    /// The task whose detail sheet is open (P1-E).
    @State private var selectedTask: TaskModel?
    @State private var showSettings = false
    @State private var showAssistant = false
    @State private var showDialPicker = false
    @State private var showQuickAdd = false
    @State private var searchText = ""
    /// AI search result (P4-7): the structured filter applied locally. Nil ⇒ plain text contains.
    @State private var aiFilter: AISearchFilter?

    var body: some View {
        NavigationStack {
            Group {
                if tasks.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        let dialItems = sectographItems
                        let busy = busyItems
                        if !dialItems.isEmpty || !busy.isEmpty {
                            GeometryReader { geo in
                                // The dial draws as a centered square inside this frame; reconstruct the
                                // same SectographLayout so a tap maps to a block (or a free time slot).
                                let side = min(geo.size.width, geo.size.height)
                                let ox = (geo.size.width - side) / 2
                                let oy = (geo.size.height - side) / 2
                                let layout = SectographLayout(size: CGSize(width: side, height: side), ringWidth: 24)
                                SectographDial(items: dialItems, busy: busy, labels: dialLabels,
                                                titles: dialTitles, style: dialStyle)
                                    .contentShape(Rectangle())
                                    .gesture(SpatialTapGesture().onEnded { v in
                                        handleDialTap(CGPoint(x: v.location.x - ox, y: v.location.y - oy),
                                                      layout: layout, items: dialItems)
                                    })
                                    .simultaneousGesture(
                                        LongPressGesture(minimumDuration: 0.45).onEnded { _ in showDialPicker = true })
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityHint("Tap a block to open it, tap a free slot to add a task, long-press to change the dial style")
                            }
                            .frame(height: 240)
                            .padding(.top, theme.spacing.sm)
                            .padding(.horizontal, theme.spacing.xl)
                        }
                        taskList
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showAssistant = true } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("AI assistant")
                }
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
            .sheet(isPresented: $showSettings) {
                SettingsView().environment(services)
            }
            .sheet(isPresented: $showAssistant) {
                AIAssistantView().environment(services)
            }
            .sheet(isPresented: $showDialPicker) {
                NavigationStack { DialStylePicker() }
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddView().environment(auth).environment(services)
            }
            .searchable(text: $searchText, prompt: services.aiConsentEnabled ? "Search or ask…" : "Search")
            .onChange(of: searchText) { _, _ in aiFilter = nil } // editing invalidates the AI filter
            .onSubmit(of: .search) {
                Task { aiFilter = await services.aiSearch(searchText) } // NL → structured filter, else plain text
            }
            .onAppear {
                #if DEBUG
                if AppConfig.showSettingsOnLaunch { showSettings = true }
                if AppConfig.showAssistantOnLaunch {
                    UserDefaults.standard.set(true, forKey: "aiConsentEnabled")
                    showAssistant = true
                }
                #endif
            }
        }
    }

    /// Tasks after applying the search (AI structured filter when present, else plain title contains).
    private var visibleTasks: [TaskModel] {
        guard !searchText.isEmpty || aiFilter != nil else { return tasks }
        return tasks.filter(matchesSearch)
    }

    private func matchesSearch(_ task: TaskModel) -> Bool {
        guard let filter = aiFilter else {
            return searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText)
        }
        if !filter.includeCompleted && task.status == .done { return false }
        if let text = filter.text, !text.isEmpty, !task.title.localizedCaseInsensitiveContains(text) { return false }
        if !filter.priorities.isEmpty, !filter.priorities.map(\.asPriority).contains(task.priority) { return false }
        if let before = filter.dueBefore, let due = task.dueAt, due > before { return false }
        if let after = filter.dueAfter, let due = task.dueAt, due < after { return false }
        return true
    }

    private var taskList: some View {
        List {
            ForEach(visibleTasks) { task in
                TaskRow(
                    title: task.title,
                    isDone: task.status == .done,
                    priorityLevel: task.priority.rawValue,
                    list: list(for: task).map {
                        TaskRow.ListBadge(name: $0.name, systemImage: $0.icon, colorHex: $0.colorHex)
                    },
                    tags: tagNames(for: task),
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
                .contextMenu { rowContextMenu(task) } // long-press quick actions (FR-TASK-190)
            }
        }
    }

    /// Long-press context menu for a task row: complete, reschedule presets, open, delete (FR-TASK-190).
    @ViewBuilder
    private func rowContextMenu(_ task: TaskModel) -> some View {
        Button { Task { await toggleComplete(task) } } label: {
            Label(task.status == .done ? "Reopen" : "Mark done",
                  systemImage: task.status == .done ? "arrow.uturn.left" : "checkmark.circle")
        }
        Menu {
            ForEach(ReschedulePreset.allCases.filter { $0.date(from: services.clock.now()) != nil }) { preset in
                Button { Task { await reschedule(task, preset: preset) } } label: {
                    Label(preset.label, systemImage: preset.systemImage)
                }
            }
        } label: { Label("Reschedule", systemImage: "calendar.badge.clock") }
        Button { selectedTask = task } label: { Label("Open", systemImage: "info.circle") }
        Divider()
        Button(role: .destructive) { Task { await delete(task) } } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Apply a one-tap reschedule preset to a task's due date (FR-TASK-160).
    private func reschedule(_ task: TaskModel, preset: ReschedulePreset) async {
        guard let date = preset.date(from: services.clock.now()) else { return }
        await mutation.reschedule(task, dueAt: date)
        if AppConfig.isLiveSync { await services.syncOnce() }
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

    /// Resolve a task's tag ids to names for the row pills.
    private func tagNames(for task: TaskModel) -> [String] {
        task.tagIds.compactMap { id in allTags.first { $0.id == id }?.name }
    }

    /// Map today's scheduled/due tasks to dial blocks (P2): scheduled ranges become arcs; a due-only
    /// task becomes a short marker sliver at its due time. Tinted by the task's list color.
    private var sectographItems: [SectographItem] {
        let calendar = Calendar.current
        let now = services.clock.now()
        func minute(_ date: Date) -> Int? {
            guard calendar.isDate(date, inSameDayAs: now) else { return nil }
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        return tasks.compactMap { task in
            let taskList = list(for: task)
            let color = taskList?.colorHex
            let icon = taskList?.icon
            let done = task.status == .done
            if let start = task.scheduledStart, let startMinute = minute(start) {
                let endMinute = task.scheduledEnd.flatMap(minute) ?? min(1440, startMinute + 60)
                return SectographItem(id: task.id, startMinute: startMinute, endMinute: endMinute,
                                      colorHex: color, kind: .span, symbolName: icon, isDone: done)
            } else if let due = task.dueAt, let dueMinute = minute(due) {
                // Due-only tasks read as instant markers (a dashed spoke + the list icon), not fat arcs.
                return SectographItem(id: task.id, startMinute: dueMinute, endMinute: min(1440, dueMinute + 20),
                                      colorHex: color, kind: .instant, symbolName: icon, isDone: done)
            }
            return nil
        }
    }

    /// VoiceOver labels for the dial's blocks (P2-6) — "Title, at 9:00 AM".
    private var dialLabels: [String: String] {
        let calendar = Calendar.current
        func timeString(_ minute: Int) -> String {
            let date = calendar.date(from: DateComponents(hour: minute / 60, minute: minute % 60)) ?? .now
            return date.formatted(date: .omitted, time: .shortened)
        }
        var result: [String: String] = [:]
        for item in sectographItems {
            if let task = tasks.first(where: { $0.id == item.id }) {
                result[item.id] = "\(task.title), at \(timeString(item.startMinute))"
            }
        }
        return result
    }

    /// On-arc display titles for the dial blocks (P5-5 aurora) — keyed by item id, like `dialLabels`.
    private var dialTitles: [String: String] {
        var result: [String: String] = [:]
        for item in sectographItems {
            if let task = tasks.first(where: { $0.id == item.id }) { result[item.id] = task.title }
        }
        return result
    }

    /// Map a tap on the dial to an action: hit a block → open it; hit a free slot in the ring band →
    /// quick-add a task; tap the center/outside → ignore. Uses the pure ``SectographLayout`` geometry.
    private func handleDialTap(_ point: CGPoint, layout: SectographLayout, items: [SectographItem]) {
        if let id = layout.hitTest(at: point, items: items),
           let task = tasks.first(where: { $0.id == id }) {
            selectedTask = task
        } else if layout.ringContains(point) {
            showQuickAdd = true
        }
    }

    /// Calendar free/busy blocks for the dial overlay (P2-5): real EventKit data when authorized,
    /// or sample blocks under DEBUG `-calendarDemo` so the overlay is screenshot-verifiable.
    private var busyItems: [SectographItem] {
        #if DEBUG
        if AppConfig.isCalendarDemo {
            return [
                SectographItem(id: "busy:standup", startMinute: 11 * 60, endMinute: 12 * 60),
                SectographItem(id: "busy:review", startMinute: 14 * 60, endMinute: 15 * 60 + 30),
            ]
        }
        #endif
        return services.calendar.busyItems(now: services.clock.now())
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
