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
    @State private var showRecurrenceEditor = false
    /// Members of the task's shared list, for the assignee picker (journey G04-S08); empty unless shared.
    @State private var shareMembers: [ShareMemberDTO] = []
    @State private var assigneeLoading = false

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
                if services.conflictedEntityIds.contains(task.id) {
                    Section {
                        ConflictResolverCard(
                            mineLabel: titleDraft.isEmpty ? "(empty title)" : titleDraft,
                            theirsLabel: task.title.isEmpty ? "(empty title)" : task.title,
                            onKeepMine: { Task { await commitTextAndSchedule(); services.acknowledgeConflict(task.id) } },
                            onUseTheirs: { resetDraftsFromModel(); services.acknowledgeConflict(task.id) }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

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
                    if let rule = task.recurrence {
                        Button("Customize…") { showRecurrenceEditor = true }
                        Text(recurrenceSummary(rule)).font(.caption).foregroundStyle(.secondary)
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

                if taskShareId != nil {
                    Section {
                        if assigneeLoading && shareMembers.isEmpty {
                            HStack { Text("Loading members…").foregroundStyle(.secondary); Spacer(); ProgressView() }
                        } else if shareMembers.isEmpty {
                            Text("No members to assign yet.").foregroundStyle(.secondary)
                        } else {
                            Picker("Assigned to", selection: Binding(
                                get: { task.assigneeUserId ?? "" },
                                set: { newVal in Task { await setAssignee(newVal.isEmpty ? nil : newVal) } }
                            )) {
                                Text("Unassigned").tag("")
                                ForEach(shareMembers) { m in
                                    Text(memberLabel(m)).tag(m.userId)
                                }
                            }
                        }
                    } header: {
                        Text("Assignee")
                    } footer: {
                        Text("Only members of this shared list can be assigned. Assignment syncs to everyone.")
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
                        .swipeActions(edge: .leading) {
                            Button { Task { await promoteToSubtask(item) } } label: {
                                Label("To subtask", systemImage: "arrow.up.forward.square")
                            }.tint(.blue)
                        }
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
            .sheet(isPresented: $showRecurrenceEditor) {
                RecurrenceEditorView(initial: task.recurrence ?? RecurrenceRule(freq: .weekly)) { rule in
                    Task { await mutate { await mutation.setRecurrence(task, rule) } }
                }
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
                resetDraftsFromModel()
                loadReminders()
                loadChecklist()
            }
            .task { await loadMembersIfShared() }
        }
    }

    /// Reload the editable drafts from the (server-authoritative) model — used on appear and when the
    /// user chooses "Use newer" after a conflict (journey G04-S15).
    private func resetDraftsFromModel() {
        titleDraft = task.title
        notesDraft = task.notes ?? ""
        hasDueDate = task.dueAt != nil
        dueDraft = task.dueAt ?? Date()
    }

    // MARK: - Assignee (journey G04-S08)

    /// The share id of the task's list, when the list is shared — gates the assignee picker.
    private var taskShareId: String? {
        guard let listId = task.listId else { return nil }
        return lists.first { $0.id == listId }?.shareId
    }

    private func loadMembersIfShared() async {
        guard let shareId = taskShareId else { return }
        assigneeLoading = true
        defer { assigneeLoading = false }
        shareMembers = (try? await services.apiClient.shareMembers(shareId: shareId)) ?? []
    }

    /// Assign (or clear) via the server's membership-validated endpoint, then reconcile via sync.
    private func setAssignee(_ userId: String?) async {
        guard task.assigneeUserId != userId else { return }
        do {
            _ = try await services.apiClient.assignTask(taskId: task.id, assigneeUserId: userId)
            task.assigneeUserId = userId
            if AppConfig.isLiveSync { await services.syncOnce() } // pull authoritative serverVersion
        } catch {
            // Leave the prior assignment on failure; the picker reflects the unchanged model.
        }
    }

    private func memberLabel(_ m: ShareMemberDTO) -> String {
        let who = m.userId == services.currentOwnerId ? "You" : String(m.userId.prefix(8))
        return "\(who) · \(m.role.capitalized)"
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

    /// Promote a checklist item into a first-class schedulable subtask (parentTaskId = this task),
    /// then remove the checklist item (FR-SUB-060).
    private func promoteToSubtask(_ item: ChecklistItemModel) async {
        let creator = TaskCreation(context: modelContext, engine: services.syncEngine,
                                   ownerId: task.ownerId, clock: services.clock, idGenerator: services.idGenerator)
        let id = await creator.createTask(title: item.text)
        var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let sub = try? modelContext.fetch(descriptor).first {
            await mutation.setParent(sub, task.id)
        }
        await checklistMutation.delete(item)
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

    /// One-line plain-English description of a recurrence rule for the Repeat section (G04-S11).
    private func recurrenceSummary(_ rule: RecurrenceRule) -> String {
        let unit: String
        switch rule.freq {
        case .daily: unit = "day"
        case .weekly: unit = "week"
        case .monthly: unit = "month"
        case .yearly: unit = "year"
        }
        var s = rule.interval == 1 ? "Every \(unit)" : "Every \(rule.interval) \(unit)s"
        if rule.freq == .weekly, let days = rule.byWeekday, !days.isEmpty {
            let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            s += " on " + days.sorted().map { names[($0 - 1) % 7] }.joined(separator: ", ")
        }
        if let until = rule.until {
            s += ", until " + until.formatted(date: .abbreviated, time: .omitted)
        } else if let count = rule.count {
            s += ", \(count)×"
        }
        return s
    }
}
