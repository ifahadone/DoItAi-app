import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// The focus-timer surface (AppSpec §5.3, DevelopmentPlan P2-4). Shows the live elapsed time for the
/// running ``FocusController`` session and lets the user pause/resume/stop; stopping logs the elapsed
/// minutes onto the task's `actualMinutes`.
struct FocusTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppServices.self) private var services

    var body: some View {
        NavigationStack {
            VStack(spacing: theme.spacing.xl) {
                if let session = services.focus.session {
                    Text(session.taskTitle)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)

                    TimelineView(.periodic(from: .now, by: 1)) { tick in
                        let elapsed = session.elapsedSeconds(at: tick.date.timeIntervalSince1970)
                        Text(Self.clockString(elapsed))
                            .font(.system(size: 64, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(session.isRunning ? theme.colors.accent : .secondary)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }

                    HStack(spacing: theme.spacing.lg) {
                        Button {
                            session.isRunning ? services.focus.pause() : services.focus.resume()
                        } label: {
                            Label(session.isRunning ? "Pause" : "Resume",
                                  systemImage: session.isRunning ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            Task { await stop() }
                        } label: {
                            Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, theme.spacing.xl)
                } else {
                    EmptyStateView(title: "No focus session", systemImage: "timer",
                                   message: "Start a focus timer from a task.")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
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
