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
                    analytics
                    if habits.isEmpty {
                        EmptyStateView(title: "No habits yet", systemImage: "flame",
                                       message: "Track a habit in Lists → Routines & Habits to build a streak.")
                            .frame(minHeight: 180)
                    } else {
                        Text("Habits").font(.headline)
                        ForEach(habits) { habitCard($0) }
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
        }
    }

    private var summary: some View {
        let now = services.clock.now()
        let calendar = Calendar.current
        let doneToday = tasks.filter {
            $0.status == .done && ($0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
        }.count
        let focusMinutes = tasks.reduce(0) { $0 + ($1.actualMinutes ?? 0) }
        return HStack(spacing: theme.spacing.md) {
            statCard(value: "\(doneToday)", label: "Done today", systemImage: "checkmark.circle.fill")
            statCard(value: "\(focusMinutes)m", label: "Focused", systemImage: "timer")
            statCard(value: "\(habits.count)", label: "Habits", systemImage: "flame.fill")
        }
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
            EmptyStateView(title: "Not enough data yet", systemImage: "chart.bar",
                           message: "Create and complete a few tasks to see your insights.")
                .frame(minHeight: 160)
        } else {
            let completion = Analytics.completion(stats, in: interval, now: now)
            let byHour = Analytics.productivityByHour(stats, calendar: .current)
            let byList = Analytics.timeByList(stats)
            let backlog = Analytics.backlog(stats, now: now)
            let focus = Analytics.focus(stats)

            completionCard(completion)
            productivityCard(byHour)
            if !byList.isEmpty { timeAllocationCard(byList) }
            backlogCard(backlog)
            if focus.sessions > 0 { focusCard(focus) }
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
        cardShell("Time by list", systemImage: "chart.pie") {
            Chart(slices.prefix(6).map { $0 }) { slice in
                BarMark(x: .value("Minutes", slice.minutes), y: .value("List", listName(slice.listId)))
                    .foregroundStyle(theme.colors.accent)
            }
            .frame(height: CGFloat(min(slices.count, 6)) * 28 + 12)
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
        return VStack(alignment: .leading, spacing: theme.spacing.sm) {
            HStack {
                Text(habit.name.isEmpty ? "Untitled habit" : habit.name).font(.subheadline.weight(.medium))
                Spacer()
                Text("🔥 \(habit.streakCurrent)").font(.subheadline)
            }
            Text("Best \(habit.streakLongest) · \(HabitHeatmap.completedCount(in: days)) of last 70 days")
                .font(.caption2).foregroundStyle(.secondary)
            heatmap(days)
        }
        .padding(theme.spacing.md)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.medium))
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
