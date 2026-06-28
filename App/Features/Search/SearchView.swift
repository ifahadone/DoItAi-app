import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Dedicated cross-content search (AppSpec S15): on-device, offline full-text over tasks, lists, tags,
/// and Keeper notes, grouped by type, with a type scope and recent searches. Pushed from Lists; relies
/// on the parent navigation stack. Complements Today's inline `.searchable` (which is task-only + AI NL).
struct SearchView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services
    @Environment(\.theme) private var theme

    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil && !$0.archived && $0.statusRaw != 4 },
           sort: \TaskModel.createdAt, order: .reverse)
    private var tasks: [TaskModel]
    @Query(filter: #Predicate<TaskListModel> { $0.deletedAt == nil }, sort: \TaskListModel.sortIndex)
    private var lists: [TaskListModel]
    @Query(filter: #Predicate<TagModel> { $0.deletedAt == nil }, sort: \TagModel.name)
    private var tags: [TagModel]
    @Query(filter: #Predicate<NoteModel> { $0.deletedAt == nil }, sort: \NoteModel.updatedAt, order: .reverse)
    private var notes: [NoteModel]

    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var selectedTask: TaskModel?
    @AppStorage("recentSearches") private var recentRaw = ""
    /// AI natural-language interpretation of the query (journey G11-S04). Nil ⇒ plain-text search.
    @State private var aiFilter: AISearchFilter?
    @State private var aiInterpreting = false
    /// Manual refinement filters (journey G11-S03).
    @State private var showFilters = false
    @State private var fIncludeCompleted = true
    @State private var fPriorities: Set<Priority> = []
    @State private var fListId: String?
    @State private var fTagIds: Set<String> = []

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", tasks = "Tasks", lists = "Lists", notes = "Notes"
        var id: String { rawValue }
    }

    private var q: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasQuery: Bool { !q.isEmpty }
    /// Active when the user has typed, AI-interpreted, or set a manual filter — drives results vs. recents.
    private var isSearching: Bool { hasQuery || aiFilter != nil || hasActiveFilters }

    private var hasActiveFilters: Bool {
        !fIncludeCompleted || !fPriorities.isEmpty || fListId != nil || !fTagIds.isEmpty
    }

    private var taskHits: [TaskModel] {
        guard hasQuery || hasActiveFilters || aiFilter != nil else { return [] }
        return tasks.filter(matchesTask)
    }

    /// Combine the typed text, the AI-interpreted filter (G11-S04), and the manual filters (G11-S03).
    private func matchesTask(_ task: TaskModel) -> Bool {
        // Text: prefer the AI filter's extracted text, else the raw query.
        let needle = (aiFilter?.text?.isEmpty == false ? aiFilter?.text : nil) ?? q
        if !needle.isEmpty {
            let hit = task.title.localizedCaseInsensitiveContains(needle)
                || (task.notes?.localizedCaseInsensitiveContains(needle) ?? false)
            if !hit { return false }
        }
        // Completed: hidden only if both the manual toggle and the AI filter allow hiding.
        let allowCompleted = fIncludeCompleted && (aiFilter?.includeCompleted ?? true)
        if !allowCompleted && task.status == .done { return false }
        // Priorities: union of manual + AI; task must match one when any are requested.
        var wantedPriorities = fPriorities
        if let ai = aiFilter { wantedPriorities.formUnion(ai.priorities.map(\.asPriority)) }
        if !wantedPriorities.isEmpty, !wantedPriorities.contains(task.priority) { return false }
        // List: manual id, plus an AI list-name hint.
        if let fListId, task.listId != fListId { return false }
        if let hint = aiFilter?.listHint, !hint.isEmpty {
            let name = lists.first { $0.id == task.listId }?.name ?? ""
            if !name.localizedCaseInsensitiveContains(hint) { return false }
        }
        // Tags: union of manual ids + AI tag names→ids; task must carry all requested.
        var wantedTagIds = fTagIds
        if let ai = aiFilter {
            let aiIds = ai.tags.compactMap { name in tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id }
            wantedTagIds.formUnion(aiIds)
        }
        if !wantedTagIds.isEmpty, !wantedTagIds.isSubset(of: Set(task.tagIds)) { return false }
        // Due window from the AI filter.
        if let before = aiFilter?.dueBefore, let due = task.dueAt, due > before { return false }
        if let after = aiFilter?.dueAfter, let due = task.dueAt, due < after { return false }
        return true
    }
    private var listHits: [TaskListModel] {
        hasQuery ? lists.filter { $0.name.localizedCaseInsensitiveContains(q) } : []
    }
    private var tagHits: [TagModel] {
        hasQuery ? tags.filter { $0.name.localizedCaseInsensitiveContains(q) } : []
    }
    private var noteHits: [NoteModel] {
        guard hasQuery else { return [] }
        return notes.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q) }
    }
    private var noMatches: Bool { taskHits.isEmpty && listHits.isEmpty && tagHits.isEmpty && noteHits.isEmpty }

    private var recents: [String] { recentRaw.split(separator: "\n").map(String.init) }
    private var showTasks: Bool { scope == .all || scope == .tasks }
    private var showLists: Bool { scope == .all || scope == .lists }
    private var showNotes: Bool { scope == .all || scope == .notes }

    var body: some View {
        List {
            if !isSearching {
                if recents.isEmpty {
                    ContentUnavailableView("Search DoIT", systemImage: "magnifyingglass",
                                           description: Text("Find tasks, lists, tags, and notes. Ask in plain language with AI on."))
                } else {
                    Section("Recent") {
                        ForEach(recents, id: \.self) { r in
                            Button { query = r; runAISearch() } label: {
                                Label(r, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                            }
                        }
                        Button("Clear recents", role: .destructive) { recentRaw = "" }
                    }
                }
            } else {
                if aiInterpreting {
                    Section { Label("Interpreting…", systemImage: "sparkles").foregroundStyle(.secondary) }
                } else if let chips = interpretedChips {
                    Section {
                        Label(chips, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                    } header: { Text("Interpreted") }
                }
                if noMatches {
                    ContentUnavailableView.search(text: q.isEmpty ? "your filters" : q)
                } else {
                    resultsSections
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showFilters = true } label: {
                    Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill"
                                                        : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filters")
            }
        }
        .sheet(isPresented: $showFilters) {
            SearchFiltersSheet(includeCompleted: $fIncludeCompleted, priorities: $fPriorities,
                               listId: $fListId, tagIds: $fTagIds, lists: lists, tags: tags)
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: services.aiConsentEnabled ? "Search or ask…" : "Tasks, lists, tags, notes")
        .onChange(of: query) { _, _ in aiFilter = nil } // editing invalidates the AI interpretation
        .onSubmit(of: .search) { recordRecent(); runAISearch() }
        .safeAreaInset(edge: .top) {
            if isSearching {
                Picker("Type", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailView(task: task).environment(auth).environment(services)
        }
    }

    /// The grouped result sections (tasks/lists/tags/notes), shown once a search is active.
    @ViewBuilder private var resultsSections: some View {
        if showTasks, !taskHits.isEmpty {
            Section("Tasks") {
                ForEach(taskHits) { task in
                    Button { selectedTask = task } label: { taskRow(task) }
                }
            }
        }
        if showLists, !listHits.isEmpty {
            Section("Lists") {
                ForEach(listHits) { list in
                    NavigationLink { ListDetailView(list: list) } label: {
                        ListHeader(name: list.name, systemImage: list.icon, colorHex: list.colorHex,
                                   count: tasks.filter { $0.listId == list.id }.count)
                    }
                }
            }
        }
        if scope == .all, !tagHits.isEmpty {
            Section("Tags") {
                ForEach(tagHits) { tag in TagPill(name: tag.name, colorHex: tag.colorHex) }
            }
        }
        if showNotes, !noteHits.isEmpty {
            Section("Notes") {
                ForEach(noteHits) { note in
                    NavigationLink { NoteEditorView(note: note) } label: { noteRow(note) }
                }
            }
        }
    }

    /// Plain-English summary of the AI interpretation (G11-S04), shown as an "Interpreted" chip row.
    private var interpretedChips: String? {
        guard let f = aiFilter else { return nil }
        var parts: [String] = []
        if let t = f.text, !t.isEmpty { parts.append("“\(t)”") }
        if !f.priorities.isEmpty { parts.append(f.priorities.map { "P\(5 - $0.asPriority.rawValue)" }.joined(separator: "/")) }
        if !f.tags.isEmpty { parts.append(f.tags.map { "#\($0)" }.joined(separator: " ")) }
        if let l = f.listHint, !l.isEmpty { parts.append("in \(l)") }
        if f.dueBefore != nil || f.dueAfter != nil { parts.append("by date") }
        if !f.includeCompleted { parts.append("open only") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Ask the server to turn the query into a structured filter (journey G11-S04). No-op without consent.
    private func runAISearch() {
        guard services.aiConsentEnabled, hasQuery else { aiFilter = nil; return }
        Task {
            aiInterpreting = true
            aiFilter = await services.aiSearch(q)
            aiInterpreting = false
        }
    }

    private func taskRow(_ task: TaskModel) -> some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.status == .done ? theme.colors.accent : .secondary)
            Text(task.title).foregroundStyle(.primary).lineLimit(1)
            Spacer()
        }
    }

    private func noteRow(_ note: NoteModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title.isEmpty ? "Untitled note" : note.title).foregroundStyle(.primary).lineLimit(1)
            if !note.body.isEmpty {
                Text(note.body).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func recordRecent() {
        guard hasQuery else { return }
        var list = recents.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        list.insert(q, at: 0)
        recentRaw = list.prefix(8).joined(separator: "\n")
    }
}

/// Manual search refinement filters (journey G11-S03): completed visibility, priority, list, and tags.
private struct SearchFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var includeCompleted: Bool
    @Binding var priorities: Set<Priority>
    @Binding var listId: String?
    @Binding var tagIds: Set<String>
    let lists: [TaskListModel]
    let tags: [TagModel]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include completed", isOn: $includeCompleted)
                }
                Section("Priority") {
                    ForEach([Priority.p1, .p2, .p3, .p4], id: \.self) { p in
                        Button {
                            if priorities.contains(p) { priorities.remove(p) } else { priorities.insert(p) }
                        } label: {
                            HStack {
                                PriorityChip(level: p.rawValue)
                                Spacer()
                                if priorities.contains(p) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                if !lists.isEmpty {
                    Section("List") {
                        Picker("List", selection: Binding(get: { listId ?? "" }, set: { listId = $0.isEmpty ? nil : $0 })) {
                            Text("Any").tag("")
                            ForEach(lists) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                if !tags.isEmpty {
                    Section("Tags") {
                        ForEach(tags) { tag in
                            Button {
                                if tagIds.contains(tag.id) { tagIds.remove(tag.id) } else { tagIds.insert(tag.id) }
                            } label: {
                                HStack {
                                    Text(tag.name).foregroundStyle(.primary)
                                    Spacer()
                                    if tagIds.contains(tag.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { includeCompleted = true; priorities = []; listId = nil; tagIds = [] }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
