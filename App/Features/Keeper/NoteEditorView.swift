import SwiftUI
import SwiftData
import SyncCore

/// Edit a single note (Keeper — added feature; see DevelopmentPlan §10.5). Title + free-form body, with a pin toggle. Text edits are
/// committed on Done (each a no-op if unchanged) and flushed when live-syncing.
struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Bindable var note: NoteModel

    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil && !$0.archived && $0.statusRaw != 4 },
           sort: \TaskModel.createdAt, order: .reverse)
    private var tasks: [TaskModel]
    @Query(filter: #Predicate<NoteFolderModel> { $0.deletedAt == nil }, sort: \NoteFolderModel.sortIndex)
    private var folders: [NoteFolderModel]

    @State private var titleDraft = ""
    @State private var bodyDraft = ""
    @State private var showTaskPicker = false
    @State private var showFolderPicker = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $titleDraft, axis: .vertical)
                    .font(.headline)
            }
            Section("Note") {
                TextEditor(text: $bodyDraft)
                    .frame(minHeight: 260)
                    .overlay(alignment: .topLeading) {
                        if bodyDraft.isEmpty {
                            Text("Write anything you want to keep…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            Section("Folder") {
                Button { showFolderPicker = true } label: {
                    HStack {
                        Label(currentFolderName, systemImage: "folder")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section("Linked task") {
                if let linked = tasks.first(where: { $0.id == note.taskId }) {
                    HStack {
                        Image(systemName: "checklist").foregroundStyle(.secondary)
                        Text(linked.title).lineLimit(1)
                        Spacer()
                        Button("Unlink", role: .destructive) { Task { await unlinkTask() } }
                            .font(.caption)
                    }
                } else if note.taskId != nil {
                    // Linked to a task not in the local store (archived / another device).
                    Button("Unlink task", role: .destructive) { Task { await unlinkTask() } }
                } else {
                    Button { showTaskPicker = true } label: { Label("Link to a task", systemImage: "link") }
                }
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await togglePin() } } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(note.pinned ? "Unpin note" : "Pin note")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { Task { await commit(); dismiss() } }
            }
        }
        .onAppear {
            titleDraft = note.title
            bodyDraft = note.body
        }
        .sheet(isPresented: $showTaskPicker) {
            NavigationStack {
                List {
                    if tasks.isEmpty {
                        Text("No tasks to link yet.").foregroundStyle(.secondary)
                    }
                    ForEach(tasks) { task in
                        Button { Task { await linkTask(task) } } label: {
                            Text(task.title).foregroundStyle(.primary).lineLimit(1)
                        }
                    }
                }
                .navigationTitle("Link to task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showTaskPicker = false } }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFolderPicker) {
            NavigationStack {
                List {
                    Button { Task { await move(to: nil) } } label: {
                        HStack {
                            Label("All Notes (no folder)", systemImage: "tray")
                            Spacer()
                            if note.folderId == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        .foregroundStyle(.primary)
                    }
                    ForEach(folders) { folder in
                        Button { Task { await move(to: folder.id) } } label: {
                            HStack {
                                Label(folder.name, systemImage: folder.icon)
                                Spacer()
                                if note.folderId == folder.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                .navigationTitle("Move note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showFolderPicker = false } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// Display name for the note's current folder (journey G10-S07).
    private var currentFolderName: String {
        folders.first { $0.id == note.folderId }?.name ?? "All Notes (no folder)"
    }

    private func move(to folderId: String?) async {
        await mutation.move(note, toFolderId: folderId)
        await syncIfLive()
        showFolderPicker = false
    }

    private func linkTask(_ task: TaskModel) async {
        await mutation.setTaskId(note, task.id)
        await syncIfLive()
        showTaskPicker = false
    }

    private func unlinkTask() async {
        await mutation.setTaskId(note, nil)
        await syncIfLive()
    }

    private var mutation: NoteMutation {
        NoteMutation(context: modelContext, engine: services.syncEngine, clock: services.clock,
                     idGenerator: services.idGenerator, ownerId: services.currentOwnerId)
    }

    private func commit() async {
        await mutation.setTitle(note, titleDraft)
        await mutation.setBody(note, bodyDraft)
        await syncIfLive()
    }

    private func togglePin() async {
        await mutation.setPinned(note, !note.pinned)
        await syncIfLive()
    }

    private func syncIfLive() async { if AppConfig.isLiveSync { await services.syncOnce() } }
}
