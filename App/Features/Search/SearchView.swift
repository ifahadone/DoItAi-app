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

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", tasks = "Tasks", lists = "Lists", notes = "Notes"
        var id: String { rawValue }
    }

    private var q: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasQuery: Bool { !q.isEmpty }

    private var taskHits: [TaskModel] {
        guard hasQuery else { return [] }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(q) || ($0.notes?.localizedCaseInsensitiveContains(q) ?? false) }
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
            if !hasQuery {
                if recents.isEmpty {
                    ContentUnavailableView("Search DoIT", systemImage: "magnifyingglass",
                                           description: Text("Find tasks, lists, tags, and notes."))
                } else {
                    Section("Recent") {
                        ForEach(recents, id: \.self) { r in
                            Button { query = r } label: {
                                Label(r, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                            }
                        }
                        Button("Clear recents", role: .destructive) { recentRaw = "" }
                    }
                }
            } else if noMatches {
                ContentUnavailableView.search(text: q)
            } else {
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
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Tasks, lists, tags, notes")
        .onSubmit(of: .search) { recordRecent() }
        .safeAreaInset(edge: .top) {
            if hasQuery {
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
