import SwiftUI
import SyncCore
import DesignSystem

/// Completion drill-down (journey G12-S04): the contributing tasks behind the completion metric — what
/// you completed, what's overdue, and what you created in the selected range — so the analytics stay
/// trustworthy (every chart can be traced back to real tasks, per US-INS-020).
struct CompletionDetailView: View {
    let tasks: [TaskModel]
    let interval: DateInterval
    let now: Date

    private var completed: [TaskModel] {
        tasks.filter { $0.status == .done && ($0.completedAt.map { interval.contains($0) } ?? false) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    private var overdue: [TaskModel] {
        tasks.filter { $0.status != .done && ($0.dueAt.map { $0 < now } ?? false) }
            .sorted { ($0.dueAt ?? .distantPast) < ($1.dueAt ?? .distantPast) }
    }
    private var created: [TaskModel] {
        tasks.filter { interval.contains($0.createdAt) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            section("Completed", completed, system: "checkmark.circle.fill", tint: .green) { $0.completedAt }
            section("Overdue", overdue, system: "exclamationmark.circle.fill", tint: .red) { $0.dueAt }
            section("Created in range", created, system: "plus.circle", tint: .blue) { $0.createdAt }
        }
        .navigationTitle("Completion")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [TaskModel], system: String, tint: Color,
                         date: @escaping (TaskModel) -> Date?) -> some View {
        Section {
            if items.isEmpty {
                Text("None").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(items) { task in
                    HStack(spacing: 10) {
                        Image(systemName: system).foregroundStyle(tint)
                        Text(task.title).lineLimit(1)
                        Spacer(minLength: 8)
                        if let d = date(task) {
                            Text(d.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("\(title) · \(items.count)")
        }
    }
}
