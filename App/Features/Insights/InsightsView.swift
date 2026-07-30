import SwiftUI
import SwiftData
import SyncCore
import DesignSystem
import Charts

/// The Insights tab (AppSpec §5.9, DevelopmentPlan P3-5): a quick summary + per-habit streak cards
/// with a "don't break the chain" completion heatmap (the last 70 days). Streaks come from the
/// server-authoritative routine fields; the heatmap from its synced `completions`.
struct InsightsView: View {
    @Environment(\.theme) private var theme
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<RoutineModel> { $0.deletedAt == nil && $0.isHabit == true }, sort: \RoutineModel.name)
    private var habits: [RoutineModel]
    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil })
    private var tasks: [TaskModel]
    @Query(filter: #Predicate<TaskListModel> { $0.deletedAt == nil })
    private var lists: [TaskListModel]

    @State private var range: AnalyticsRange = .week
    @State private var showAssistant = false
    @State private var showDetails = false

    enum AnalyticsRange: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month"
        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.lg) {
                    summary
                        .doitEntrance(order: 0)
                    reviewCard
                        .doitEntrance(order: 1)
                    glanceInsight
                        .doitEntrance(order: 2)

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                            showDetails.toggle()
                        }
                    } label: {
                        HStack {
                            Label(showDetails ? "Hide details" : "Explore trends",
                                  systemImage: showDetails ? "chevron.up" : "chart.xyaxis.line")
                            Spacer()
                            Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                .font(.caption)
                        }
                        .font(.headline)
                        .padding(.vertical, theme.spacing.sm)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.accent)

                    if showDetails {
                        VStack(alignment: .leading, spacing: theme.spacing.lg) {
                            analytics
                            if habits.isEmpty {
                                EmptyStateView(title: "No habits yet", systemImage: "flame",
                                               message: "Track a habit in Lists → Routines & Habits to build a streak.")
                                    .frame(minHeight: 180)
                            } else {
                                DoITSectionHeading("Habits", subtitle: "Current streaks and the last 70 days.")
                                ForEach(habits) { habitCard($0) }
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(theme.spacing.xl)
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAssistant = true } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("AI assistant & weekly review")
                }
            }
            .sheet(isPresented: $showAssistant) {
                AIAssistantView().environment(services)
            }
        }
    }

    /// Entry to the weekly AI review (AppSpec S14 primary action), surfaced from Insights rather than
    /// only from Today. Opening the assistant guides the user to enable AI if consent is off.
    private var reviewCard: some View {
        Button { showAssistant = true } label: {
            cardShell("Weekly review", systemImage: "sparkles") {
                HStack {
                    Text(services.aiConsentEnabled
                         ? "Generate an AI summary of your week."
                         : "Turn on AI to generate a weekly review.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        let now = services.clock.now()
        let calendar = Calendar.current
        let doneToday = tasks.filter {
            $0.status == .done && ($0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
        }.count
        let focusMinutes = tasks.reduce(0) { $0 + ($1.actualMinutes ?? 0) }
        return VStack(alignment: .leading, spacing: theme.spacing.md) {
            Text("At a glance")
                .font(.title2.bold())
            HStack(spacing: 0) {
                summaryMetric(value: "\(doneToday)", label: "Done", icon: "checkmark.circle.fill")
                Divider().frame(height: 42)
                summaryMetric(value: "\(focusMinutes)m", label: "Focused", icon: "timer")
                Divider().frame(height: 42)
                summaryMetric(value: "\(habits.count)", label: "Habits", icon: "flame.fill")
            }
            .padding(.vertical, theme.spacing.sm)
        }
    }

    private var glanceInsight: some View {
        let stats = taskStats
        let now = services.clock.now()
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let completion = Analytics.completion(stats, in: DateInterval(start: weekStart, end: now), now: now)
        let rate = completion.completionRatePct.map { "\($0)%" } ?? "—"
        return VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text("Last 7 days")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(rate)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("completion")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                if completion.overdue > 0 {
                    Label("\(completion.overdue) overdue", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text("\(completion.completed) completed from \(completion.created) created.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(theme.spacing.lg)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))
    }

    private func summaryMetric(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Label(value, systemImage: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.colors.accent)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Analytics (P6-3, AppSpec §5.9)

    private var taskStats: [TaskStat] {
        tasks.map { task in
            TaskStat(id: task.id, isDone: task.status == .done, createdAt: task.createdAt, dueAt: task.dueAt,
                     completedAt: task.completedAt, scheduledStart: task.scheduledStart, scheduledEnd: task.scheduledEnd,
                     actualMinutes: task.actualMinutes, listId: task.listId)
        }
    }

    private var interval: DateInterval {
        let now = services.clock.now()
        let start = Calendar.current.date(byAdding: .day, value: -range.days, to: now) ?? now
        return DateInterval(start: start, end: now)
    }

    @ViewBuilder
    private var analytics: some View {
        let now = services.clock.now()
        let stats = taskStats
        Picker("Range", selection: $range) {
            ForEach(AnalyticsRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)

        if stats.count < 3 {
            // Progressive empty state (AppSpec S14): the message escalates with how much data exists.
            EmptyStateView(
                title: stats.isEmpty ? "Your insights start here" : "Almost there",
                systemImage: "chart.bar",
                message: stats.isEmpty
                    ? "Add a few tasks and complete them — patterns appear after your first couple of days."
                    : "Keep logging. A couple more scheduled or completed tasks unlock your trends."
            )
            .frame(minHeight: 160)
        } else {
            let completion = Analytics.completion(stats, in: interval, now: now)
            let byHour = Analytics.productivityByHour(stats, calendar: .current)
            let byList = Analytics.timeByList(stats)
            let backlog = Analytics.backlog(stats, now: now)
            let focus = Analytics.focus(stats)
            let eva = estimateVsActual

            NavigationLink {
                CompletionDetailView(tasks: tasks, interval: interval, now: now)
            } label: { completionCard(completion) }
            .buttonStyle(.plain)
            if eva.count > 0 { estimateVsActualCard(eva) }
            productivityCard(byHour)
            if !byList.isEmpty { timeAllocationCard(byList) }
            backlogCard(backlog)
            if focus.sessions > 0 { focusCard(focus) }
        }
    }

    /// Planned (scheduled block duration) vs logged minutes, over tasks that have both — drives the
    /// estimate-accuracy card. Computed locally from the live tasks (no server aggregation needed).
    private var estimateVsActual: (planned: Int, actual: Int, count: Int) {
        var planned = 0, actual = 0, count = 0
        for task in tasks where task.actualMinutes != nil {
            guard let start = task.scheduledStart, let end = task.scheduledEnd else { continue }
            let mins = max(0, Int(end.timeIntervalSince(start) / 60))
            guard mins > 0 else { continue }
            planned += mins
            actual += task.actualMinutes ?? 0
            count += 1
        }
        return (planned, actual, count)
    }

    private func estimateVsActualCard(_ e: (planned: Int, actual: Int, count: Int)) -> some View {
        let ofPlan = e.planned > 0 ? Int((Double(e.actual) / Double(e.planned)) * 100) : nil
        return cardShell("Estimate vs actual", systemImage: "scalemass") {
            HStack(spacing: theme.spacing.lg) {
                metric("\(e.planned)m", "Planned")
                metric("\(e.actual)m", "Actual")
                metric(ofPlan.map { "\($0)%" } ?? "—", "Of plan")
                metric("\(e.count)", "Blocks")
            }
        }
    }

    private func focusCard(_ f: Analytics.Focus) -> some View {
        cardShell("Focus time", systemImage: "timer") {
            HStack(spacing: theme.spacing.lg) {
                metric("\(f.totalMinutes)m", "Total")
                metric("\(f.sessions)", "Sessions")
                metric("\(f.avgMinutes)m", "Avg")
            }
        }
    }

    private func completionCard(_ c: Analytics.Completion) -> some View {
        cardShell("Completion", systemImage: "checkmark.seal") {
            HStack(spacing: theme.spacing.lg) {
                metric("\(c.completionRatePct.map { "\($0)%" } ?? "—")", "Completion")
                metric("\(c.onTimePct.map { "\($0)%" } ?? "—")", "On time")
                metric("\(c.completed)/\(c.created)", "Done/new")
                metric("\(c.overdue)", "Overdue")
            }
        }
    }

    private func productivityCard(_ hours: [Int]) -> some View {
        cardShell("Productivity by hour", systemImage: "clock") {
            VStack(alignment: .leading, spacing: 4) {
                Chart(Array(hours.enumerated()), id: \.offset) { hour, count in
                    BarMark(x: .value("Hour", hour), y: .value("Done", count))
                        .foregroundStyle(theme.colors.accent)
                }
                .chartXScale(domain: 0...23)
                .chartXAxis { AxisMarks(values: [0, 6, 12, 18]) }
                .frame(height: 90)
                if let peak = Analytics.peakHour(taskStats, calendar: .current) {
                    Text("Most productive around \(peak):00").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timeAllocationCard(_ slices: [Analytics.TimeSlice]) -> some View {
        let top = Array(slices.prefix(6))
        let maxM = max(1, top.map { $0.minutes }.max() ?? 1)
        return cardShell("Time by list", systemImage: "chart.pie") {
            VStack(spacing: theme.spacing.sm) {
                ForEach(top) { slice in
                    allocationRow(slice, maxMinutes: maxM, list: lists.first { $0.id == slice.listId })
                }
            }
        }
    }

    /// A drill-down row: list name + proportional bar + minutes. Tapping a real list opens its tasks
    /// (AppSpec S14 chart drill-down). The "No list" slice has no destination.
    @ViewBuilder
    private func allocationRow(_ slice: Analytics.TimeSlice, maxMinutes: Int, list: TaskListModel?) -> some View {
        let row = HStack(spacing: theme.spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(listName(slice.listId)).font(.caption).foregroundStyle(.primary)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.colors.accent.opacity(0.85))
                        .frame(width: max(2, geo.size.width * CGFloat(slice.minutes) / CGFloat(maxMinutes)), height: 6)
                }
                .frame(height: 6)
            }
            Text("\(slice.minutes)m").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if list != nil { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
        }
        if let list {
            NavigationLink { ListDetailView(list: list) } label: { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private func backlogCard(_ b: Analytics.Backlog) -> some View {
        cardShell("Backlog health", systemImage: "tray.full") {
            HStack(spacing: theme.spacing.lg) {
                metric("\(b.inbox)", "Open")
                metric("\(b.overdue)", "Overdue")
                metric("\(b.medianAgeDays)d", "Median age")
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func cardShell<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.medium))
            content()
        }
        .padding(theme.spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.medium))
    }

    private func listName(_ id: String?) -> String {
        guard let id else { return "No list" }
        return lists.first { $0.id == id }?.name ?? "List"
    }

    private func statCard(value: String, label: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).foregroundStyle(theme.colors.accent)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, theme.spacing.md)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.medium))
    }

    private func habitCard(_ habit: RoutineModel) -> some View {
        let days = HabitHeatmap.days(completions: Set(habit.completions), days: 70, today: services.clock.now())
        return NavigationLink {
            HabitDetailView(habit: habit).environment(services)
        } label: {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                HStack {
                    Text(habit.name.isEmpty ? "Untitled habit" : habit.name).font(.subheadline.weight(.medium))
                    Spacer()
                    Label("\(habit.streakCurrent)", systemImage: "flame.fill")
                        .font(.subheadline).labelStyle(.titleAndIcon).foregroundStyle(.orange)
                }
                Text("Best \(habit.streakLongest) · \(HabitHeatmap.completedCount(in: days)) of last 70 days")
                    .font(.caption2).foregroundStyle(.secondary)
                heatmap(days)
            }
            .padding(theme.spacing.md)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.medium))
        }
        .buttonStyle(.plain)
    }

    private func heatmap(_ days: [HeatmapDay]) -> some View {
        let rows = Array(repeating: GridItem(.fixed(12), spacing: 3), count: 7)
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: rows, spacing: 3) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.completed ? theme.colors.statusDone : theme.colors.separator.opacity(0.35))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel("Completion heatmap, \(HabitHeatmap.completedCount(in: days)) of last \(days.count) days")
    }
}
