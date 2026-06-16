import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// The Lists tab (AppSpec §4, DevelopmentPlan P1-F). Shows synced lists (with task counts) and tags,
/// supports create/delete for both, and drills into a list to see + manage its tasks. Replaces the
/// Phase-0 placeholder.
struct ListsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<TaskListModel> { $0.deletedAt == nil }, sort: \TaskListModel.sortIndex)
    private var lists: [TaskListModel]
    @Query(filter: #Predicate<TagModel> { $0.deletedAt == nil }, sort: \TagModel.name)
    private var tags: [TagModel]
    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil && !$0.archived && $0.statusRaw != 4 })
    private var tasks: [TaskModel]

    @State private var creatingList = false
    @State private var creatingTag = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RoutinesView()
                    } label: {
                        Label("Routines & Habits", systemImage: "repeat")
                    }
                    NavigationLink {
                        KeeperView()
                    } label: {
                        Label("Keeper — Notes & Folders", systemImage: "books.vertical.fill")
                    }
                }

                Section("Lists") {
                    if lists.isEmpty {
                        Text("No lists yet — tap + to create one.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(lists) { list in
                        NavigationLink {
                            ListDetailView(list: list)
                        } label: {
                            ListHeader(name: list.name, systemImage: list.icon,
                                       colorHex: list.colorHex, count: taskCount(for: list))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await deleteList(list) } } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Section("Tags") {
                    if tags.isEmpty {
                        Text("No tags yet — tap + to create one.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(tags) { tag in
                        TagPill(name: tag.name, colorHex: tag.colorHex)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await deleteTag(tag) } } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { newName = ""; creatingList = true } label: { Label("New List", systemImage: "folder.badge.plus") }
                        Button { newName = ""; creatingTag = true } label: { Label("New Tag", systemImage: "tag") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New list or tag")
                }
            }
            .alert("New List", isPresented: $creatingList) {
                TextField("Name", text: $newName)
                Button("Create") { Task { await createList() } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New Tag", isPresented: $creatingTag) {
                TextField("Name", text: $newName)
                Button("Create") { Task { await createTag() } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Data

    private func taskCount(for list: TaskListModel) -> Int {
        tasks.filter { $0.listId == list.id }.count
    }

    private var ownerId: String {
        if case let .signedIn(userId) = auth.state, let userId { return userId }
        return "local-user"
    }

    private var listMutation: ListMutation {
        ListMutation(context: modelContext, engine: services.syncEngine, clock: services.clock,
                     idGenerator: services.idGenerator, ownerId: ownerId)
    }
    private var tagMutation: TagMutation {
        TagMutation(context: modelContext, engine: services.syncEngine, clock: services.clock,
                    idGenerator: services.idGenerator, ownerId: ownerId)
    }

    private func createList() async { await listMutation.create(name: newName); await syncIfLive() }
    private func createTag() async { await tagMutation.create(name: newName); await syncIfLive() }
    private func deleteList(_ list: TaskListModel) async { await listMutation.delete(list); await syncIfLive() }
    private func deleteTag(_ tag: TagModel) async { await tagMutation.delete(tag); await syncIfLive() }

    private func syncIfLive() async { if AppConfig.isLiveSync { await services.syncOnce() } }
}
