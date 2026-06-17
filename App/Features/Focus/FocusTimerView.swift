import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// The focus surface (AppSpec §5.3, DevelopmentPlan P2-4): a full-screen Sectograph watch-face dial of
/// today, with the focused task's block glowing and a center hub that counts the session down with a
/// progress ring. Pause/resume/stop; stopping logs the elapsed minutes onto the task's `actualMinutes`.
struct FocusTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppServices.self) private var services

    // The day's tasks + lists, so the dial shows today around the focused block (same source as Today).
    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil && !$0.archived },
           sort: \TaskModel.createdAt, order: .reverse)
    private var tasks: [TaskModel]
    @Query(filter: #Predicate<TaskListModel> { $0.deletedAt == nil })
    private var lists: [TaskListModel]

    private let runningAccent = Color(hex: "#FF453A") ?? .red
    private let pausedAccent = Color(hex: "#FF9F0A") ?? .orange
    /// When the task has no scheduled block to size the ring against, fall back to a 25-min focus block.
    private let defaultTargetMinutes = 25

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.black)
    }

    @ViewBuilder private var content: some View {
        if let session = services.focus.session {
            let dayItems = DayDial.items(tasks: tasks, lists: lists, now: services.clock.now())
            let titles = DayDial.titles(tasks: tasks, items: dayItems)
            let targetSec = Double(targetMinutes(session, items: dayItems) * 60)

            VStack(spacing: 28) {
                Text(session.taskTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 32)

                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    let elapsed = session.elapsedSeconds(at: tick.date.timeIntervalSince1970)
                    let over = elapsed >= targetSec
                    let remaining = max(0, targetSec - elapsed)
                    let progress = targetSec > 0 ? elapsed / targetSec : 0
                    let accent = session.isRunning ? runningAccent : pausedAccent
                    let caption = !session.isRunning ? "PAUSED" : (over ? "OVERTIME" : "FOCUS")

                    FocusDialView(
                        items: dayItems,
                        titles: titles,
                        nowMinute: dialMinute(tick.date),
                        focusItemId: session.taskId,
                        centerTitle: session.taskTitle,
                        centerTime: Self.clockString(over ? elapsed : remaining),
                        centerCaption: caption,
                        progress: progress,
                        accent: accent
                    )
                    .padding(.horizontal, 16)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                }

                controls(session)
            }
            .padding(.vertical, 24)
        } else {
            EmptyStateView(title: "No focus session", systemImage: "timer",
                           message: "Start a focus timer from a task.")
        }
    }

    @ViewBuilder private func controls(_ session: FocusSession) -> some View {
        HStack(spacing: 16) {
            Button {
                session.isRunning ? services.focus.pause() : services.focus.resume()
            } label: {
                Label(session.isRunning ? "Pause" : "Resume",
                      systemImage: session.isRunning ? "pause.fill" : "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button(role: .destructive) {
                Task { await stop() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(runningAccent)
        }
        .padding(.horizontal, 28)
    }

    /// Target minutes for the countdown ring: the focused task's scheduled-block duration if it's on the
    /// dial today, otherwise a sensible 25-minute focus block.
    private func targetMinutes(_ session: FocusSession, items: [SectographItem]) -> Int {
        if let item = items.first(where: { $0.id == session.taskId }), !item.isInstant, item.durationMinutes > 0 {
            return item.durationMinutes
        }
        return defaultTargetMinutes
    }

    private func dialMinute(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func stop() async {
        guard let result = services.focus.stop() else { dismiss(); return }
        let taskId = result.taskId
        var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == taskId })
        descriptor.fetchLimit = 1
        if let task = try? modelContext.fetch(descriptor).first {
            let mutation = TaskMutation(context: modelContext, engine: services.syncEngine,
                                        clock: services.clock, idGenerator: services.idGenerator)
            await mutation.addActualMinutes(task, result.minutes)
            if AppConfig.isLiveSync { await services.syncOnce() }
        }
        dismiss()
    }

    static func clockString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
