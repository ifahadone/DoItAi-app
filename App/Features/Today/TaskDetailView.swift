import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Edit a single task (AppSpec §5.2, DevelopmentPlan P1-E). Presented as a sheet from the Today list.
/// Edits flow through ``TaskMutation`` (local write + sparse-patch outbox op); when live-syncing each
/// change flushes immediately. Text edits are committed on Done; toggles/pickers apply on change.
struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services

    @Bindable var task: TaskModel

    @Query(filter: #Predicate<TaskListModel> { $0.deletedAt == nil }, sort: \TaskListModel.name)
    private var lists: [TaskListModel]
    @Query(filter: #Predicate<TagModel> { $0.deletedAt == nil }, sort: \TagModel.name)
    private var tags: [TagModel]

    @State private var titleDraft = ""
    @State private var notesDraft = ""
    @State private var hasDueDate = false
    @State private var dueDraft = Date()

    private var mutation: TaskMutation {
        TaskMutation(context: modelContext, engine: services.syncEngine,
                     clock: services.clock, idGenerator: services.idGenerator)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $titleDraft, axis: .vertical)
                    Toggle("Completed", isOn: Binding(
                        get: { task.status == .done },
                        set: { _ in Task { await mutate { await mutation.toggleComplete(task) } } }
                    ))
                }

                Section("Priority") {
                    Picker("Priority", selection: Binding(
                        get: { task.priority },
                        set: { newValue in Task { await mutate { await mutation.setPriority(task, newValue) } } }
                    )) {
                        Text("None").tag(Priority.none)
                        Text("P4 · Low").tag(Priority.p4)
                        Text("P3").tag(Priority.p3)
                        Text("P2").tag(Priority.p2)
                        Text("P1 · Urgent").tag(Priority.p1)
                    }
                }

                Section("Schedule") {
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDraft)
                    }
                }

                if !lists.isEmpty {
                    Section("List") {
                        Picker("List", selection: Binding(
                            get: { task.listId ?? "" },
                            set: { newValue in Task { await mutate { await mutation.assign(task, toListId: newValue.isEmpty ? nil : newValue) } } }
                        )) {
                            Text("None").tag("")
                            ForEach(lists) { Text($0.name).tag($0.id) }
                        }
                    }
                }

                if !tags.isEmpty {
                    Section("Tags") {
                        ForEach(tags) { tag in
                            Button { Task { await mutate { await toggleTag(tag) } } } label: {
                                HStack {
                                    Text(tag.name).foregroundStyle(.primary)
                                    Spacer()
                                    if task.tagIds.contains(tag.id) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notesDraft, axis: .vertical).lineLimit(3...8)
                }

                Section {
                    Button(role: .destructive) {
                        Task { await mutate { await mutation.delete(task) }; dismiss() }
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Task { await commitTextAndSchedule(); dismiss() } }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                titleDraft = task.title
                notesDraft = task.notes ?? ""
                hasDueDate = task.dueAt != nil
                dueDraft = task.dueAt ?? Date()
            }
        }
    }

    /// Commit the free-text + schedule edits (each is a no-op if unchanged), then sync once.
    private func commitTextAndSchedule() async {
        await mutation.setTitle(task, titleDraft)
        await mutation.setNotes(task, notesDraft)
        await mutation.reschedule(task, dueAt: hasDueDate ? dueDraft : nil)
        await syncIfLive()
    }

    /// Toggle one tag's membership on the task.
    private func toggleTag(_ tag: TagModel) async {
        var ids = task.tagIds
        if let index = ids.firstIndex(of: tag.id) { ids.remove(at: index) } else { ids.append(tag.id) }
        await mutation.setTags(task, tagIds: ids)
    }

    /// Run a single mutation then flush (used by the on-change toggles/pickers).
    private func mutate(_ action: () async -> Void) async {
        await action()
        await syncIfLive()
    }

    private func syncIfLive() async {
        if AppConfig.isLiveSync { await services.syncOnce() }
    }
}
