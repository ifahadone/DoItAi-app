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
    @State private var showingFocus = false

    @State private var reminders: [ReminderModel] = []
    @State private var checklistItems: [ChecklistItemModel] = []
    @State private var newChecklistText = ""
    @State private var showLocationReminder = false
    @State private var showTimeReminder = false
    @State private var timeDraft = Date().addingTimeInterval(3600)

    private var mutation: TaskMutation {
        TaskMutation(context: modelContext, engine: services.syncEngine,
                     clock: services.clock, idGenerator: services.idGenerator)
    }

    private var reminderMutation: ReminderMutation {
        ReminderMutation(context: modelContext, engine: services.syncEngine, clock: services.clock,
                         idGenerator: services.idGenerator, ownerId: services.currentOwnerId)
    }

    private var checklistMutation: ChecklistMutation {
        ChecklistMutation(context: modelContext, engine: services.syncEngine, clock: services.clock,
                          idGenerator: services.idGenerator, ownerId: services.currentOwnerId)
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

                Section("Energy") {
                    Picker("Energy", selection: Binding(
                        get: { task.energy },
                        set: { newValue in Task { await mutate { await mutation.setEnergy(task, newValue) } } }
                    )) {
                        Text("Any").tag(Energy?.none)
                        Text("Low").tag(Energy?.some(.low))
                        Text("Medium").tag(Energy?.some(.med))
                        Text("High").tag(Energy?.some(.high))
                    }
                }

                Section("Estimate") {
                    Picker("Estimated duration", selection: Binding(
                        get: { task.estimatedMinutes },
                        set: { newValue in Task { await mutate { await mutation.setEstimatedMinutes(task, newValue) } } }
                    )) {
                        Text("None").tag(Int?.none)
                        Text("15m").tag(Int?.some(15))
                        Text("30m").tag(Int?.some(30))
                        Text("45m").tag(Int?.some(45))
                        Text("1h").tag(Int?.some(60))
                        Text("1h 30m").tag(Int?.some(90))
                        Text("2h").tag(Int?.some(120))
                        Text("3h").tag(Int?.some(180))
                        Text("4h").tag(Int?.some(240))
                    }
                }

                Section {
                    Picker("Repeat", selection: Binding(
                        get: { task.recurrence?.freq },
                        set: { freq in Task { await mutate { await mutation.setRecurrence(task, freq.map { RecurrenceRule(freq: $0) }) } } }
                    )) {
                        Text("Never").tag(RecurrenceRule.Freq?.none)
                        Text("Daily").tag(RecurrenceRule.Freq?.some(.daily))
                        Text("Weekly").tag(RecurrenceRule.Freq?.some(.weekly))
                        Text("Monthly").tag(RecurrenceRule.Freq?.some(.monthly))
                        Text("Yearly").tag(RecurrenceRule.Freq?.some(.yearly))
                    }
                    if task.recurrence != nil {
                        Button("Edit this event only") {
                            Task { await mutate { await mutation.detachKeepingSeries(task) } }
                        }
                    }
                } header: {
                    Text("Repeat")
                } footer: {
                    if task.recurrence != nil {
                        Text("Completing this task creates the next one automatically. Changing Repeat applies to this and all future occurrences; “Edit this event only” detaches this one and keeps the series going.")
                    }
                }

                Section("Schedule") {
                    Toggle("Has due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDraft)
                    }
                }

                Section("Reminders") {
                    ForEach(reminders) { reminder in reminderRow(reminder) }
                        .onDelete { offsets in Task { await deleteReminders(at: offsets) } }
                    Menu {
                        Button { showTimeReminder = true } label: { Label("At a time…", systemImage: "clock") }
                        Button { showLocationReminder = true } label: { Label("At a place…", systemImage: "mappin.and.ellipse") }
                    } label: {
                        Label("Add Reminder", systemImage: "plus")
                    }
                }

                Section("Subtasks") {
                    ForEach(checklistItems) { item in
                        Button { Task { await toggleChecklist(item) } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.done ? .green : .secondary)
                                Text(item.text)
                                    .strikethrough(item.done)
                                    .foregroundStyle(item.done ? .secondary : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in Task { await deleteChecklist(at: offsets) } }

                    HStack {
                        Image(systemName: "plus.circle").foregroundStyle(.secondary)
                        TextField("Add subtask", text: $newChecklistText)
                            .onSubmit { Task { await addChecklistItem() } }
                        if !newChecklistText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add") { Task { await addChecklistItem() } }
                        }
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

                // Collaboration thread (P5-5). Server-connected builds only — it's a live thread shared
                // with the list's members, so it has nothing to show in a pure-local build.
                if AppConfig.isLiveSync {
                    TaskCommentsSection(taskId: task.id)
                }

                Section {
                    Button {
                        services.focus.start(taskId: task.id, title: task.title)
                        showingFocus = true
                    } label: {
                        Label("Start Focus", systemImage: "timer")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await mutate { await mutation.delete(task) }; dismiss() }
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .sheet(isPresented: $showingFocus) {
                FocusTimerView().environment(services)
            }
            .sheet(isPresented: $showLocationReminder) {
                LocationReminderEditor { region in Task { await addLocationReminder(region) } }
            }
            .sheet(isPresented: $showTimeReminder) {
                NavigationStack {
                    Form { DatePicker("Remind me at", selection: $timeDraft) }
                        .navigationTitle("Time Reminder")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") { showTimeReminder = false; Task { await addTimeReminder() } }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showTimeReminder = false }
                            }
                        }
                }
                .presentationDetents([.medium])
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
                loadReminders()
                loadChecklist()
            }
        }
    }

    /// One reminder row — a place (kind 2) or a time (kind 0/1).
    @ViewBuilder
    private func reminderRow(_ reminder: ReminderModel) -> some View {
        if reminder.kind == 2, let region = reminder.region {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.center.name ?? "Location")
                    Text("\(Int(region.radius)) m · \(triggerText(region))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: "mappin.and.ellipse") }
        } else if let fireAt = reminder.fireAt {
            Label(fireAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
        } else {
            Label("Reminder", systemImage: "bell")
        }
    }

    private func triggerText(_ region: ReminderRegion) -> String {
        switch (region.onEntry, region.onExit) {
        case (true, true): return "arrive & leave"
        case (true, false): return "on arrive"
        case (false, true): return "on leave"
        case (false, false): return "—"
        }
    }

    private func loadReminders() {
        let taskId = task.id
        reminders = (try? modelContext.fetch(FetchDescriptor<ReminderModel>(
            predicate: #Predicate { $0.taskId == taskId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    private func loadChecklist() {
        let taskId = task.id
        checklistItems = (try? modelContext.fetch(FetchDescriptor<ChecklistItemModel>(
            predicate: #Predicate { $0.taskId == taskId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.ord), SortDescriptor(\.createdAt)]))) ?? []
    }

    private func addChecklistItem() async {
        let text = newChecklistText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await checklistMutation.create(taskId: task.id, text: text, ord: checklistItems.count)
        newChecklistText = ""
        await syncIfLive()
        loadChecklist()
    }

    private func toggleChecklist(_ item: ChecklistItemModel) async {
        await checklistMutation.toggle(item)
        await syncIfLive()
        loadChecklist()
    }

    private func deleteChecklist(at offsets: IndexSet) async {
        for index in offsets where checklistItems.indices.contains(index) {
            await checklistMutation.delete(checklistItems[index])
        }
        await syncIfLive()
        loadChecklist()
    }

    private func addTimeReminder() async {
        await reminderMutation.createAbsolute(taskId: task.id, fireAt: timeDraft)
        _ = await services.scheduleReminders() // re-arm the 64-cap notification window (P1-I)
        await syncIfLive()
        loadReminders()
    }

    private func addLocationReminder(_ region: ReminderRegion) async {
        await reminderMutation.createLocation(taskId: task.id, region: region)
        _ = services.rearmLocationReminders() // re-arm geofence monitoring (P3-7)
        await syncIfLive()
        loadReminders()
    }

    private func deleteReminders(at offsets: IndexSet) async {
        for index in offsets where reminders.indices.contains(index) {
            await reminderMutation.delete(reminders[index])
        }
        await syncIfLive()
        loadReminders()
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
