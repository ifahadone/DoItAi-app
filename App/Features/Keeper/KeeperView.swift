import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Keeper — a personal knowledge keeper (added feature; see DevelopmentPlan §10.5): notes in colored folders for easy
/// access. Reached from the Lists tab; drills folders → notes → the note editor. Everything round-trips
/// through the same entity-agnostic sync as tasks/lists. Designed to live inside the Lists tab's
/// `NavigationStack` (no nested stack here).
struct KeeperView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<NoteFolderModel> { $0.deletedAt == nil }, sort: \NoteFolderModel.sortIndex)
    private var folders: [NoteFolderModel]
    @Query(filter: #Predicate<NoteModel> { $0.deletedAt == nil })
    private var notes: [NoteModel]

    @State private var creatingFolder = false
    @State private var newFolderName = ""

    var body: some View {
        List {
            Section {
                NavigationLink { NoteListView(folder: nil) } label: {
                    Label {
                        HStack { Text("All Notes"); Spacer(); Text("\(notes.count)").foregroundStyle(.secondary) }
                    } icon: { Image(systemName: "note.text").foregroundStyle(.tint) }
                }
            }

            Section("Folders") {
                if folders.isEmpty {
                    Text("No folders yet — tap the + to create one.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(folders) { folder in
                    NavigationLink { NoteListView(folder: folder) } label: { folderRow(folder) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { Task { await deleteFolder(folder) } } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Keeper")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { newFolderName = ""; creatingFolder = true } label: { Image(systemName: "folder.badge.plus") }
                    .accessibilityLabel("New folder")
            }
        }
        .alert("New Folder", isPresented: $creatingFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { Task { await createFolder() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: NoteFolderModel) -> some View {
        Label {
            HStack {
                Text(folder.name)
                Spacer()
                Text("\(notes.filter { $0.folderId == folder.id }.count)").foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: folder.icon).foregroundStyle(Color(hex: folder.colorHex) ?? .accentColor)
        }
    }

    private var folderMutation: NoteFolderMutation {
        NoteFolderMutation(context: modelContext, engine: services.syncEngine, clock: services.clock,
                           idGenerator: services.idGenerator, ownerId: services.currentOwnerId)
    }

    private func createFolder() async {
        await folderMutation.create(name: newFolderName)
        await syncIfLive()
    }
    private func deleteFolder(_ folder: NoteFolderModel) async {
        await folderMutation.delete(folder)
        await syncIfLive()
    }
    private func syncIfLive() async { if AppConfig.isLiveSync { await services.syncOnce() } }
}

/// Notes within a folder (or all unfiled/everything when `folder == nil`). Pinned notes float to the top.
struct NoteListView: View {
    let folder: NoteFolderModel?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<NoteModel> { $0.deletedAt == nil })
    private var allNotes: [NoteModel]

    @State private var creating = false
    @State private var newTitle = ""

    private var notes: [NoteModel] {
        let scoped = folder == nil ? allNotes : allNotes.filter { $0.folderId == folder!.id }
        return scoped.sorted { a, b in
            a.pinned != b.pinned ? a.pinned : a.updatedAt > b.updatedAt
        }
    }

    var body: some View {
        List {
            if notes.isEmpty {
                Text("No notes yet — tap + to add one.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                NavigationLink { NoteEditorView(note: note) } label: { noteRow(note) }
                    .swipeActions(edge: .leading) {
                        Button { Task { await togglePin(note) } } label: {
                            Label(note.pinned ? "Unpin" : "Pin", systemImage: note.pinned ? "pin.slash" : "pin")
                        }.tint(.orange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { Task { await delete(note) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle(folder?.name ?? "All Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { newTitle = ""; creating = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New note")
            }
        }
        .alert("New Note", isPresented: $creating) {
            TextField("Title", text: $newTitle)
            Button("Add") { Task { await addNote() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func noteRow(_ note: NoteModel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if note.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.body).lineLimit(1)
                if !note.body.isEmpty {
                    Text(note.body).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var noteMutation: NoteMutation {
        NoteMutation(context: modelContext, engine: services.syncEngine, clock: services.clock,
                     idGenerator: services.idGenerator, ownerId: services.currentOwnerId)
    }

    private func addNote() async {
        await noteMutation.create(title: newTitle, folderId: folder?.id)
        await syncIfLive()
    }
    private func delete(_ note: NoteModel) async { await noteMutation.delete(note); await syncIfLive() }
    private func togglePin(_ note: NoteModel) async { await noteMutation.setPinned(note, !note.pinned); await syncIfLive() }
    private func syncIfLive() async { if AppConfig.isLiveSync { await services.syncOnce() } }
}
