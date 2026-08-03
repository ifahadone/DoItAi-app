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
        filter: #Predicate<TaskModel> { $0.deletedAt == nil && !$0.archived && $0.statusRaw != 4 },
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

    /// Active habits, for the Today habit-ring card (journey G02-S06). Excludes paused/archived ones.
    @Query(filter: #Predicate<RoutineModel> { $0.deletedAt == nil && $0.isHabit == true && !$0.archived && !$0.paused })
    private var habits: [RoutineModel]

    /// The user's chosen day-dial style (P5-5 sectograph variants), persisted across launches.
    @AppStorage("dialStyle") private var dialStyleRaw = DialStyle.watchFace.rawValue
    private var dialStyle: DialStyle { DialStyle(rawValue: dialStyleRaw) ?? .watchFace }

    /// The task whose detail sheet is open (P1-E).
    @State private var selectedTask: TaskModel?
    @State private var showSettings = false
    @State private var showAssistant = false
    @State private var showDialPicker = false
    @State private var showQuickAdd = false
    /// Minute under the finger while scrubbing the dial (drag to scan the day); nil when not scrubbing.
    @State private var scrubMinute: Int?
    @State private var searchText = ""
    /// AI search result (P4-7): the structured filter applied locally. Nil ⇒ plain text contains.
    @State private var aiFilter: AISearchFilter?
    /// AI morning brief surfaced on Today (FR-TODAY-120) — generated on tap, cached for the session.
    @State private var briefText = ""
    @State private var briefing = false

    /// The most-recently completed task, surfaced as an undo toast (journey G02-S10).
    @State private var lastCompleted: TaskModel?
    @State private var toastToken = UUID()
    /// Dismiss flag for the day-health overbooked prompt (journey G02-S07).
    @State private var dismissedDayHealth = false
    /// Presents the full-screen focus timer when started from the now/next card (journey G02-S05).
    @State private var showFocus = false
    /// Progressive disclosure for Today: glance mode is the default; the user's preference persists.
    @AppStorage("todayShowsFullDay") private var showsFullDay = false

    var body: some View {
        NavigationStack {
            Group {
                if tasks.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        glanceSummary
                            .doitEntrance(order: 0)
                        let dialItems = sectographItems
                        let busy = busyItems
                        GeometryReader { geo in
                            let hasSummary = !dialCategorySummaries.isEmpty
                            let summaryWidth: CGFloat = hasSummary ? 104 : 0
                            let spacing: CGFloat = hasSummary ? 10 : 0
                            let side = min(geo.size.height, max(150, geo.size.width - summaryWidth - spacing))
                            HStack(alignment: .center, spacing: spacing) {
                                dialHero(dialItems: dialItems, busy: busy)
                                    .frame(width: side, height: side)
                                if hasSummary {
                                    dialCategorySummary
                                        .frame(width: summaryWidth)
                                        .frame(maxHeight: side)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(height: showsFullDay ? 240 : 212)
                        .padding(.top, theme.spacing.sm)
                        .padding(.bottom, theme.spacing.sm)
                        .doitEntrance(order: 1)
                        nextUpCard
                            .doitEntrance(order: 2)
                        if showsFullDay {
                            Group {
                                morningBriefCard
                                habitProgressCard
                                dayHealthBanner
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        taskList
                            .doitEntrance(order: 3)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.88), value: showsFullDay)
                }
            }
            .navigationTitle("Today")
            .overlay(alignment: .bottom) {
                if let t = lastCompleted {
                    UndoToast("Completed “\(t.title)”") { Task { await undoComplete() } }
                        .padding(.bottom, theme.spacing.sm)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: lastCompleted?.id)
            .safeAreaInset(edge: .top) {
                if services.isSyncing || services.lastSyncFailed {
                    syncBanner.padding(.horizontal).padding(.top, 4)
                }
            }
            // Open a task from a doit://task/<id> deep link once it's available locally (journey G15-S16).
            .onChange(of: services.pendingOpenTaskId) { _, id in openPendingTask(id) }
            .onAppear { openPendingTask(services.pendingOpenTaskId) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showAssistant = true } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("AI assistant")
                }
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
            .fullScreenCover(isPresented: $showFocus) {
                FocusTimerView().environment(services)
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

    /// The first line answers the only glance-mode questions: how much is left, how much is planned,
    /// and whether the user is viewing the short or detailed version of the day.
    private var glanceSummary: some View {
        let now = services.clock.now()
        let open = tasks.filter { $0.status != .done }.count
        let completed = tasks.filter { $0.status == .done }.count
        let planned = tasks.filter {
            guard let start = $0.scheduledStart else { return false }
            return Calendar.current.isDate(start, inSameDayAs: now) && $0.status != .done
        }.count

        return HStack(spacing: theme.spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(open == 0 ? "All clear" : "\(open) left today")
                    .font(.title3.weight(.bold))
            }

            Spacer()

            if planned > 0 {
                Label("\(planned) planned", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if completed > 0 {
                Label("\(completed) done", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Button {
                withAnimation(.snappy) { showsFullDay.toggle() }
            } label: {
                Label(showsFullDay ? "Glance" : "Full day",
                      systemImage: showsFullDay ? "rectangle.compress.vertical" : "list.bullet")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(showsFullDay
                ? "Shows only the most important items"
                : "Shows habits, brief, day health, and every task")
        }
        .padding(.horizontal, theme.spacing.xl)
        .padding(.top, theme.spacing.xs)
    }

    private func matchesSearch(_ task: TaskModel) -> Bool {
        guard let filter = aiFilter else {
            // Plain-text search spans title, notes, tag names, and the list name (FR-SRCH-060).
            if searchText.isEmpty { return true }
            let q = searchText
            if task.title.localizedCaseInsensitiveContains(q) { return true }
            if let notes = task.notes, notes.localizedCaseInsensitiveContains(q) { return true }
            if tagNames(for: task).contains(where: { $0.localizedCaseInsensitiveContains(q) }) { return true }
            if let name = list(for: task)?.name, name.localizedCaseInsensitiveContains(q) { return true }
            return false
        }
        if !filter.includeCompleted && task.status == .done { return false }
        if let text = filter.text, !text.isEmpty, !task.title.localizedCaseInsensitiveContains(text) { return false }
        if !filter.priorities.isEmpty, !filter.priorities.map(\.asPriority).contains(task.priority) { return false }
        if let before = filter.dueBefore, let due = task.dueAt, due > before { return false }
        if let after = filter.dueAfter, let due = task.dueAt, due < after { return false }
        // Honor the AI filter's tag + list hints locally (FR-SRCH-070): the task must carry every
        // requested tag, and (if a list is hinted) belong to a list whose name matches.
        if !filter.tags.isEmpty {
            let taskTags = Set(tagNames(for: task).map { $0.lowercased() })
            let wanted = Set(filter.tags.map { $0.lowercased() })
            if !wanted.isSubset(of: taskTags) { return false }
        }
        if let hint = filter.listHint, !hint.isEmpty {
            let listName = list(for: task)?.name ?? ""
            if !listName.localizedCaseInsensitiveContains(hint) { return false }
        }
        return true
    }

    private func dialHero(dialItems: [SectographItem], busy: [SectographItem]) -> some View {
        GeometryReader { geo in
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
                // Scrub the dial like a clock dial: drag to scan any time + see what's scheduled there.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { v in
                            scrubMinute = layout.time(at: CGPoint(x: v.location.x - ox, y: v.location.y - oy))
                        }
                        .onEnded { _ in commitScrub(layout: layout, items: dialItems) })
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45).onEnded { _ in showDialPicker = true })
                .overlay(alignment: .top) {
                    if let m = scrubMinute {
                        let info = dialReadout(at: m, layout: layout, items: dialItems)
                        HStack(spacing: 6) {
                            Text(info.time).font(.caption.weight(.semibold)).monospacedDigit()
                            if let title = info.title {
                                Circle().fill(info.color).frame(width: 6, height: 6)
                                Text(title).font(.caption).lineLimit(1)
                            } else {
                                Text("Free").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(theme.colors.separator.opacity(0.4)))
                        .allowsHitTesting(false)
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Tap a block to open it, tap a free slot to add a task, drag around the dial to scan the day, long-press to change the dial style")
        }
    }

    private struct DialCategorySummary: Identifiable {
        let id: String
        let name: String
        let colorHex: String?
        let percent: Int
    }

    private var dialCategorySummaries: [DialCategorySummary] {
        let items = sectographItems
        let total = max(1, items.reduce(0) { $0 + max(1, $1.durationMinutes) })
        var groups: [String: (name: String, colorHex: String?, minutes: Int)] = [:]
        for item in items {
            guard let task = tasks.first(where: { $0.id == item.id }) else { continue }
            let list = list(for: task)
            let id = list?.id ?? "other"
            let current = groups[id] ?? (list?.name ?? "Other", list?.colorHex, 0)
            groups[id] = (current.name, current.colorHex, current.minutes + max(1, item.durationMinutes))
        }
        return groups
            .map { id, value in
                DialCategorySummary(id: id, name: value.name, colorHex: value.colorHex,
                                    percent: Int((Double(value.minutes) / Double(total) * 100).rounded()))
            }
            .sorted { $0.percent > $1.percent }
            .prefix(4)
            .map { $0 }
    }

    private var dialCategorySummary: some View {
        VStack(spacing: 7) {
            ForEach(dialCategorySummaries) { summary in
                dialCategoryCard(summary)
            }
        }
    }

    private func dialCategoryCard(_ summary: DialCategorySummary) -> some View {
        let color = summary.colorHex.flatMap { Color(hex: $0) } ?? Color.gray.opacity(0.7)
        return VStack(alignment: .leading, spacing: 5) {
            Text(summary.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text("\(summary.percent)%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.18), lineWidth: 1))
    }

    /// Today's tasks projected for the "now → next" agenda card (FR-TODAY-110).
    private var agendaSlots: [AgendaSlotItem] {
        let cal = Calendar.current
        let now = services.clock.now()
        return tasks.compactMap { t in
            guard t.status != .done else { return nil }
            if let s = t.scheduledStart, cal.isDate(s, inSameDayAs: now) {
                return AgendaSlotItem(id: t.id, title: t.title, start: s, end: t.scheduledEnd, due: t.dueAt)
            } else if let d = t.dueAt, cal.isDate(d, inSameDayAs: now) {
                return AgendaSlotItem(id: t.id, title: t.title, due: d)
            }
            return nil
        }
    }

    /// "Now → next" agenda card: the block happening now (with minutes left) + the soonest upcoming
    /// item. Updates each minute via TimelineView; hidden when there's nothing current or upcoming.
    @ViewBuilder
    private var nextUpCard: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            let now = services.clock.now()
            let result = NextUpPlanner.compute(agendaSlots, now: now)
            if result.current != nil || result.next != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let cur = result.current {
                        HStack(spacing: 6) {
                            Circle().fill(theme.colors.accent).frame(width: 7, height: 7)
                            Text("NOW").font(.caption2.weight(.bold)).foregroundStyle(theme.colors.accent)
                            Text(cur.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            if let m = NextUpPlanner.minutesLeft(in: cur, now: now) {
                                Text("\(m)m left").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        // Make the active block actionable without leaving Today (G02-S05).
                        HStack(spacing: 8) {
                            Button { startFocus(taskId: cur.id, title: cur.title) } label: {
                                Label("Focus", systemImage: "timer")
                            }
                            Button { Task { await completeById(cur.id) } } label: {
                                Label("Complete", systemImage: "checkmark.circle")
                            }
                            Spacer()
                        }
                        .buttonStyle(.bordered).controlSize(.mini).font(.caption2)
                    }
                    if let nxt = result.next {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.secondary)
                            Text("Next").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            Text(nxt.title).font(.subheadline).lineLimit(1)
                            Spacer()
                            if let a = nxt.anchor {
                                Text(a.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.separator.opacity(0.4)))
                .padding(.horizontal, theme.spacing.xl)
                .padding(.bottom, theme.spacing.sm)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let id = (result.current ?? result.next)?.id { selectedTask = tasks.first { $0.id == id } }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Compact AI "Morning brief" card (FR-TODAY-120), shown only with AI consent. Generates on tap and
    /// is cached in @State for the session so it doesn't burn the token budget on every appearance.
    @ViewBuilder
    private var morningBriefCard: some View {
        if services.aiConsentEnabled {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                    Text("Morning brief").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if briefing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(briefText.isEmpty ? "Generate" : "Refresh") { streamBrief() }.font(.caption)
                        if !briefText.isEmpty {
                            Button {
                                withAnimation(.snappy) { briefText = "" } // dismiss; regenerate anytime (G02-S03)
                            } label: { Image(systemName: "xmark").font(.caption2) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel("Dismiss brief")
                        }
                    }
                }
                if !briefText.isEmpty {
                    Text(briefText).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, theme.spacing.xl)
            .padding(.bottom, theme.spacing.sm)
        }
    }

    private func streamBrief() {
        Task {
            briefing = true
            briefText = ""
            do {
                for try await event in await services.briefStream() {
                    if case let .text(delta) = event { briefText += delta }
                }
            } catch {
                if briefText.isEmpty { briefText = "Couldn't generate a brief right now." }
            }
            briefing = false
        }
    }

    /// Overdue (past-due, still open) tasks within the current search scope — surfaced in their own
    /// strip so they don't silently rot at the bottom of the list (journey G02-S04).
    private var overdueTasks: [TaskModel] {
        let startOfToday = Calendar.current.startOfDay(for: services.clock.now())
        return visibleTasks.filter { $0.status != .done && ($0.dueAt.map { $0 < startOfToday } ?? false) }
    }

    /// Everything not in the overdue strip (so each task appears exactly once).
    private var mainTasks: [TaskModel] {
        let overdueIds = Set(overdueTasks.map(\.id))
        return visibleTasks.filter { !overdueIds.contains($0.id) }
    }

    private var displayedOverdueTasks: [TaskModel] {
        showsFullDay ? overdueTasks : Array(overdueTasks.prefix(1))
    }

    private var displayedMainTasks: [TaskModel] {
        if showsFullDay { return mainTasks }
        return Array(
            mainTasks
                .filter { $0.status != .done }
                .sorted { lhs, rhs in
                    switch (lhs.scheduledStart ?? lhs.dueAt, rhs.scheduledStart ?? rhs.dueAt) {
                    case let (l?, r?) where l != r: return l < r
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default:
                        if lhs.priority != rhs.priority {
                            let l = lhs.priority == .none ? Int.max : lhs.priority.rawValue
                            let r = rhs.priority == .none ? Int.max : rhs.priority.rawValue
                            return l < r
                        }
                        return lhs.createdAt > rhs.createdAt
                    }
                }
                .prefix(4)
        )
    }

    private var hasMoreTasks: Bool {
        displayedOverdueTasks.count + displayedMainTasks.count
            < overdueTasks.count + mainTasks.count
    }

    private var taskList: some View {
        List {
            if !displayedOverdueTasks.isEmpty {
                Section {
                    ForEach(displayedOverdueTasks) { task in taskRow(task) }
                } header: {
                    HStack {
                        Label("Overdue · \(overdueTasks.count)", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Move to today") { Task { await rescheduleOverdueToToday() } }
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            Section {
                ForEach(displayedMainTasks) { task in taskRow(task) }
                if hasMoreTasks && !showsFullDay {
                    Button {
                        withAnimation(.snappy) { showsFullDay = true }
                    } label: {
                        HStack {
                            Text("View all \(visibleTasks.count) tasks")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            } header: {
                Text(showsFullDay ? "All tasks" : "Up next")
            }
        }
        .listStyle(.plain)
    }

    /// One task row with its tap / swipe / context-menu affordances (shared by the overdue + main
    /// sections so behaviour stays identical).
    @ViewBuilder private func taskRow(_ task: TaskModel) -> some View {
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

    /// Bulk-move every overdue task's due date to today (keeping its time-of-day), without touching
    /// scheduled blocks — overdue work shouldn't silently change, but the user can opt in (G02-S04).
    private func rescheduleOverdueToToday() async {
        let cal = Calendar.current
        let now = services.clock.now()
        for task in overdueTasks {
            guard let due = task.dueAt else { continue }
            let t = cal.dateComponents([.hour, .minute], from: due)
            let newDue = cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: now) ?? now
            await mutation.reschedule(task, dueAt: newDue)
        }
        await services.syncOnce()
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
        Button { Task { await cancelTask(task) } } label: { Label("Cancel task", systemImage: "xmark.circle") }
        Button { Task { await archiveTask(task) } } label: { Label("Archive", systemImage: "archivebox") }
        Divider()
        Button(role: .destructive) { Task { await delete(task) } } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// Cancel a task — kept (not deleted), leaves the active list (FR-TASK-180).
    private func cancelTask(_ task: TaskModel) async {
        await mutation.cancel(task)
        await services.syncOnce()
    }

    /// Archive a task — kept (not deleted), leaves the active list (FR-TASK-180).
    private func archiveTask(_ task: TaskModel) async {
        await mutation.setArchived(task, true)
        await services.syncOnce()
    }

    /// Apply a one-tap reschedule preset to a task's due date (FR-TASK-160).
    private func reschedule(_ task: TaskModel, preset: ReschedulePreset) async {
        guard let date = preset.date(from: services.clock.now()) else { return }
        await mutation.reschedule(task, dueAt: date)
        await services.syncOnce()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No tasks yet", systemImage: "checklist")
        } description: {
            Text("Tap + to capture your first task.")
        }
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
        DayDial.items(tasks: tasks, lists: lists, now: services.clock.now())
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
        DayDial.titles(tasks: tasks, items: sectographItems)
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

    /// What the dial scrub readout shows at `minute`: the time + the block scheduled there (if any).
    private func dialReadout(at minute: Int, layout: SectographLayout, items: [SectographItem]) -> (time: String, title: String?, color: Color) {
        if let item = items.first(where: { layout.contains(minute: minute, $0) }) {
            return (timeLabel(minute), dialTitles[item.id] ?? "Busy", Color(hex: item.colorHex) ?? theme.colors.accent)
        }
        return (timeLabel(minute), nil, theme.colors.accent)
    }

    /// On releasing a dial scrub: open the block under the finger, else quick-add at that free time.
    private func commitScrub(layout: SectographLayout, items: [SectographItem]) {
        defer { scrubMinute = nil }
        guard let minute = scrubMinute else { return }
        if let item = items.first(where: { layout.contains(minute: minute, $0) }),
           let task = tasks.first(where: { $0.id == item.id }) {
            selectedTask = task
        } else {
            showQuickAdd = true
        }
    }

    /// "h:mm AM" for a minute-of-day (dial scrub readout).
    private func timeLabel(_ minute: Int) -> String {
        let m = max(0, min(1439, minute))
        let date = Calendar.current.date(from: DateComponents(hour: m / 60, minute: m % 60)) ?? services.clock.now()
        return date.formatted(date: .omitted, time: .shortened)
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

    // MARK: - Habit progress (journey G02-S06)

    /// Habits scheduled for today (recurrence weekday match, or "every day" when no weekdays set),
    /// paired with whether each is already logged today. Sorted undone-first so the next nudge is on top.
    private var todayHabits: [(habit: RoutineModel, done: Bool)] {
        let now = services.clock.now()
        let cal = Calendar.current
        let key = Self.dayKey(now)
        return habits
            .filter { RoutineMaterializer.occurs(recurrence: $0.recurrence, on: now, calendar: cal) }
            .map { ($0, $0.completions.contains(key)) }
            .sorted { lhs, rhs in
                if lhs.done != rhs.done { return !lhs.done } // undone first
                return lhs.habit.name.localizedCaseInsensitiveCompare(rhs.habit.name) == .orderedAscending
            }
    }

    /// Today's habit ring + a one-tap "Done" for the next outstanding habit (journey G02-S06). Hidden
    /// when no habits are scheduled today. Once everything is logged, it shows an all-clear state.
    @ViewBuilder private var habitProgressCard: some View {
        let items = todayHabits
        if !items.isEmpty {
            let done = items.filter { $0.done }.count
            let total = items.count
            let next = items.first { !$0.done }?.habit
            HStack(spacing: 12) {
                habitRing(done: done, total: total)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Habits").font(.subheadline.weight(.semibold))
                    if let next {
                        Text("Up next: \(next.name.isEmpty ? "Untitled habit" : next.name)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text("All habits done today").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 6)
                if let next {
                    Button {
                        Task { await logHabit(next) }
                    } label: {
                        Label("Done", systemImage: "checkmark").labelStyle(.titleAndIcon)
                    }
                    .font(.caption.weight(.semibold)).buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title3)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.colors.separator.opacity(0.4)))
            .padding(.horizontal, theme.spacing.xl)
            .padding(.bottom, theme.spacing.sm)
        }
    }

    private func habitRing(done: Int, total: Int) -> some View {
        let fraction = total == 0 ? 0 : Double(done) / Double(total)
        return ZStack {
            Circle().stroke(theme.colors.separator.opacity(0.3), lineWidth: 5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(theme.colors.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)").font(.caption2.weight(.bold)).monospacedDigit()
        }
        .frame(width: 40, height: 40)
        .animation(.snappy, value: fraction)
    }

    /// A `RoutineMutation` (mirrors `RoutinesView`) for logging a habit completion from Today.
    private func mutation(for habit: RoutineModel) -> RoutineMutation {
        let ownerId: String
        if case let .signedIn(userId) = auth.state, let userId { ownerId = userId } else { ownerId = "local-user" }
        return RoutineMutation(context: modelContext, engine: services.syncEngine, apiClient: services.apiClient,
                               clock: services.clock, idGenerator: services.idGenerator, ownerId: ownerId)
    }

    private func logHabit(_ habit: RoutineModel) async {
        _ = await mutation(for: habit).logHabitToday(habit)
        await services.syncOnce()
    }

    /// "yyyy-MM-dd" day key (matches `RoutineMutation.logHabitToday` + the heatmap's completion keys).
    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }

    /// "Day health" check (journey G02-S07): true when the day is overbooked — too many tasks that still
    /// need a time block, or overdue work — so Today can offer Auto-plan to fit them in.
    private var dayHealth: (needsTime: Int, overdue: Int)? {
        let now = services.clock.now()
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        var needsTime = 0, overdue = 0
        for t in tasks where t.status != .done {
            guard let due = t.dueAt else { continue }
            if due < startOfToday { overdue += 1 }
            else if cal.isDate(due, inSameDayAs: now), t.scheduledStart == nil { needsTime += 1 }
        }
        return (needsTime >= 4 || overdue >= 3) ? (needsTime, overdue) : nil
    }

    @ViewBuilder private var dayHealthBanner: some View {
        if !dismissedDayHealth, let h = dayHealth {
            let warn = Color(hex: "#FF9F0A") ?? .orange
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(warn)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your day looks full").font(.subheadline.weight(.semibold))
                    Text(dayHealthMessage(h)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Button("Auto-plan") { showAssistant = true }
                    .font(.caption.weight(.semibold)).buttonStyle(.borderedProminent).controlSize(.small)
                Button { withAnimation(.snappy) { dismissedDayHealth = true } } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal).padding(.bottom, 4)
        }
    }

    private func dayHealthMessage(_ h: (needsTime: Int, overdue: Int)) -> String {
        var parts: [String] = []
        if h.needsTime > 0 { parts.append("\(h.needsTime) task\(h.needsTime == 1 ? "" : "s") need time") }
        if h.overdue > 0 { parts.append("\(h.overdue) overdue") }
        return parts.joined(separator: " · ") + ". Let Auto-plan fit them in."
    }

    /// Non-blocking sync/offline status banner shown at the top of Today (journey G02-S09).
    @ViewBuilder private var syncBanner: some View {
        if services.isSyncing {
            StatusBanner(.syncing, "Syncing your changes…")
        } else if services.lastSyncFailed {
            StatusBanner(.offline, "Saved on this device. We'll sync when you're back online.", actionTitle: "Retry") {
                Task { await services.syncOnce() }
            }
        }
    }

    private func toggleComplete(_ task: TaskModel) async {
        await mutation.toggleComplete(task)
        await services.syncOnce()
        if task.status == .done {
            let token = UUID(); toastToken = token
            withAnimation(.snappy) { lastCompleted = task }
            Task {
                try? await Task.sleep(for: .seconds(4))
                if toastToken == token { withAnimation(.snappy) { lastCompleted = nil } }
            }
        } else if lastCompleted?.id == task.id {
            withAnimation(.snappy) { lastCompleted = nil }
        }
    }

    /// Undo the last completion (re-open the task) and hide the toast (journey G02-S10).
    private func undoComplete() async {
        guard let task = lastCompleted else { return }
        await mutation.toggleComplete(task)
        await services.syncOnce()
        withAnimation(.snappy) { lastCompleted = nil }
    }

    private func delete(_ task: TaskModel) async {
        await mutation.delete(task)
        await services.syncOnce()
    }

    /// Start the focus timer for the now-block's task and present it full-screen (G02-S05).
    private func startFocus(taskId: String, title: String) {
        services.focus.start(taskId: taskId, title: title)
        showFocus = true
    }

    /// Complete a task by id (used by the now/next card's inline action).
    private func completeById(_ id: String) async {
        guard let task = tasks.first(where: { $0.id == id }), task.status != .done else { return }
        await toggleComplete(task)
    }

    /// Present the task detail for a deep-linked id, then clear the pending flag (journey G15-S16).
    private func openPendingTask(_ id: String?) {
        guard let id, let task = tasks.first(where: { $0.id == id }) else { return }
        selectedTask = task
        services.pendingOpenTaskId = nil
    }

    private func dueText(for task: TaskModel) -> String? {
        guard let due = task.dueAt else { return nil }
        return due.formatted(date: .abbreviated, time: .shortened)
    }
}
