import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Habit adherence drill-down (journeys G07-S16 / G12-S07): current & longest streak, grace days,
/// completion rate, the 70-day heatmap, and a one-tap "Log today" (server-authoritative streak).
struct HabitDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(AppServices.self) private var services

    @Bindable var habit: RoutineModel

    private var days: [HeatmapDay] {
        HabitHeatmap.days(completions: Set(habit.completions), days: 70, today: services.clock.now())
    }
    private var doneToday: Bool { habit.completions.contains(Self.dayKey(services.clock.now())) }
    private var completionRate: Int {
        let total = days.count
        guard total > 0 else { return 0 }
        return Int((Double(HabitHeatmap.completedCount(in: days)) / Double(total) * 100).rounded())
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    stat("\(habit.streakCurrent)", "Current")
                    Divider().frame(height: 38)
                    stat("\(habit.streakLongest)", "Best")
                    Divider().frame(height: 38)
                    stat("\(completionRate)%", "70-day")
                    Divider().frame(height: 38)
                    stat("\(habit.graceDays)", "Grace")
                }
                .frame(maxWidth: .infinity)
            }

            Section("Last 70 days") {
                heatmap
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }

            Section {
                if doneToday {
                    Label("Logged today", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    Button { Task { await logToday() } } label: {
                        Label("Log today", systemImage: "flame.fill")
                    }
                }
            } footer: {
                Text(scheduleSummary)
            }
        }
        .navigationTitle(habit.name.isEmpty ? "Habit" : habit.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var heatmap: some View {
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

    private var scheduleSummary: String {
        guard let weekdays = habit.recurrence?.weekdays, !weekdays.isEmpty else { return "Repeats every day." }
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return "Repeats on " + weekdays.sorted().map { names[($0 - 1) % 7] }.joined(separator: ", ") + "."
    }

    private func logToday() async {
        let mutation = RoutineMutation(context: modelContext, engine: services.syncEngine, apiClient: services.apiClient,
                                       clock: services.clock, idGenerator: services.idGenerator, ownerId: services.currentOwnerId)
        _ = await mutation.logHabitToday(habit)
        await services.syncOnce()
    }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
}
