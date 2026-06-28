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
    @State private var editingFolder: NoteFolderModel?

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
                        .swipeActions(edge: .leading) {
                            Button { editingFolder = folder } label: { Label("Edit", systemImage: "pencil") }
                                .tint(.indigo)
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
        .sheet(item: $editingFolder) { folder in
            FolderEditView(folder: folder) { name, colorHex, icon in
                Task {
                    await folderMutation.rename(folder, to: name)
                    await folderMutation.setAppearance(folder, colorHex: colorHex, icon: icon)
                    await syncIfLive()
                }
            }
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

/// Edit a folder's name, color and icon (journey G10-S04). Wires the existing rename/setAppearance
/// mutations, which previously had no UI.
private struct FolderEditView: View {
    @Environment(\.dismiss) private var dismiss
    let folder: NoteFolderModel
    let onSave: (_ name: String, _ colorHex: String, _ icon: String) -> Void

    @State private var name = ""
    @State private var colorHex = "#8E8E93"
    @State private var icon = "folder"

    private static let colors = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE",
                                 "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#8E8E93"]
    private static let icons = ["folder", "tray.full", "book", "briefcase", "graduationcap",
                                "house", "heart", "star", "lightbulb", "leaf", "flame", "bookmark"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Folder name", text: $name)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(Self.colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .gray)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: colorHex == hex ? 2 : 0))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Self.icons, id: \.self) { sym in
                            Image(systemName: sym)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .foregroundStyle(icon == sym ? Color.white : .primary)
                                .background(icon == sym ? (Color(hex: colorHex) ?? .accentColor) : Color.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { icon = sym }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(name.trimmingCharacters(in: .whitespaces), colorHex, icon); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { name = folder.name; colorHex = folder.colorHex; icon = folder.icon }
        }
    }
}
