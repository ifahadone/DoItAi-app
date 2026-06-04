import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.lg) {
                    summary
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
