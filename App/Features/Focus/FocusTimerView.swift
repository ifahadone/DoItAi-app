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
    private let doneAccent = Color(hex: "#34C759") ?? .green
    /// Set when the user stops — presents the planned-vs-actual completion summary (G06-S05 / S06).
    @State private var summary: FocusSummary?
    /// Minutes added to the countdown target via "Extend" during a running session (journey G06-S03).
    @State private var extraMinutes = 0
    /// Quick-note capture during a session (journey G06-S01) — appended to the task's notes.
    @State private var showNote = false
    @State private var noteDraft = ""
    /// When the task has no scheduled block to size the ring against, fall back to a 25-min focus block.
    private let defaultTargetMinutes = 25

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .overlay {
                if let summary {
                    completionOverlay(summary)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88),
                       value: summary != nil)
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
        .sheet(isPresented: $showNote) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Capture a thought…", text: $noteDraft, axis: .vertical).lineLimit(3...8)
                    } header: {
                        Text("Add to task notes")
                    }
                }
                .navigationTitle("Quick Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { showNote = false; Task { await appendNote() } }
                            .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showNote = false } }
                }
            }
            .presentationDetents([.medium])
        }
    }

    /// Append the quick note to the focused task's notes (journey G06-S01), without interrupting timing.
    private func appendNote() async {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let taskId = services.focus.session?.taskId,
              let task = tasks.first(where: { $0.id == taskId }) else { return }
        let existing = task.notes ?? ""
        let combined = existing.isEmpty ? text : existing + "\n" + text
        let mutation = TaskMutation(context: modelContext, engine: services.syncEngine,
                                    clock: services.clock, idGenerator: services.idGenerator)
        await mutation.setNotes(task, combined)
        await services.syncOnce()
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
                    .doitEntrance(order: 0, trigger: session.taskId)

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
                    .doitEntrance(order: 1, trigger: session.taskId)
                }

                controls(session)
                    .doitEntrance(order: 2, trigger: session.taskId)
            }
            .padding(.vertical, 24)
        } else {
            EmptyStateView(title: "No focus session", systemImage: "timer",
                           message: "Start a focus timer from a task.")
        }
    }

    @ViewBuilder private func controls(_ session: FocusSession) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Extend the countdown without stopping (journey G06-S03) — useful when a block runs long.
                Menu {
                    Button("+5 minutes") { extraMinutes += 5 }
                    Button("+10 minutes") { extraMinutes += 10 }
                    Button("+15 minutes") { extraMinutes += 15 }
                    if extraMinutes > 0 {
                        Button("Reset extension", role: .destructive) { extraMinutes = 0 }
                    }
                } label: {
                    Label(extraMinutes > 0 ? "Extended +\(extraMinutes)m" : "Extend",
                          systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.bordered)
                .tint(.white)

                // Jot a quick note without leaving focus (journey G06-S01).
                Button { noteDraft = ""; showNote = true } label: {
                    Label("Note", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            HStack(spacing: 16) {
                Button {
                    session.isRunning ? services.focus.pause() : services.focus.resume()
                } label: {
                    Label(session.isRunning ? "Pause" : "Resume",
                          systemImage: session.isRunning ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button(role: .destructive) {
                    beginStop(session)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(runningAccent)
            }
        }
        .padding(.horizontal, 28)
    }

    /// Target minutes for the countdown ring: the focused task's scheduled-block duration if it's on the
    /// dial today, otherwise a sensible 25-minute focus block.
    private func targetMinutes(_ session: FocusSession, items: [SectographItem]) -> Int {
        let base: Int
        if let item = items.first(where: { $0.id == session.taskId }), !item.isInstant, item.durationMinutes > 0 {
            base = item.durationMinutes
        } else {
            base = defaultTargetMinutes
        }
        return base + extraMinutes
    }

    private func dialMinute(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Stop the session and present a completion summary (planned vs actual). The user then chooses to
    /// mark the task done, save partial progress and keep it open, or discard the time (G06-S05 / S06).
    private func beginStop(_ session: FocusSession) {
        let dayItems = DayDial.items(tasks: tasks, lists: lists, now: services.clock.now())
        let planned = targetMinutes(session, items: dayItems)
        let title = session.taskTitle
        guard let result = services.focus.stop() else { dismiss(); return }
        summary = FocusSummary(taskId: result.taskId, title: title, planned: planned, actual: result.minutes)
    }

    /// Apply the chosen outcome: optionally log the focused minutes onto the task and/or mark it done.
    private func apply(_ s: FocusSummary, markDone: Bool, keepTime: Bool) async {
        let taskId = s.taskId
        var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == taskId })
        descriptor.fetchLimit = 1
        if let task = try? modelContext.fetch(descriptor).first {
            let mutation = TaskMutation(context: modelContext, engine: services.syncEngine,
                                        clock: services.clock, idGenerator: services.idGenerator)
            if keepTime && s.actual > 0 { await mutation.addActualMinutes(task, s.actual) }
            if markDone && task.status != .done { await mutation.toggleComplete(task) }
            await services.syncOnce()
        }
        dismiss()
    }

    // MARK: - Completion summary overlay (planned vs actual)

    @ViewBuilder private func completionOverlay(_ s: FocusSummary) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44)).foregroundStyle(doneAccent)
                    .symbolEffect(.bounce, value: summary != nil)
                VStack(spacing: 4) {
                    Text("Session complete").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text(s.title).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                HStack(spacing: 0) {
                    stat("Planned", "\(s.planned)m", .white.opacity(0.85))
                    Divider().frame(height: 36).overlay(.white.opacity(0.2))
                    stat("Focused", "\(s.actual)m", doneAccent)
                }
                Text(deltaText(s)).font(.caption).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button { Task { await apply(s, markDone: true, keepTime: true) } } label: {
                        Label("Mark as done", systemImage: "checkmark.circle.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(doneAccent)

                    Button { Task { await apply(s, markDone: false, keepTime: true) } } label: {
                        Label("Save progress · keep open", systemImage: "clock.arrow.circlepath")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered).tint(.white)

                    Button("Discard time") { Task { await apply(s, markDone: false, keepTime: false) } }
                        .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(Color(hex: "#1C1C1E") ?? .black, in: RoundedRectangle(cornerRadius: 24))
            .padding(24)
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func deltaText(_ s: FocusSummary) -> String {
        let d = s.actual - s.planned
        if s.planned == 0 { return "No planned duration — logged \(s.actual)m of focus." }
        if d == 0 { return "Right on plan." }
        return d > 0 ? "\(d)m over the planned block." : "\(-d)m under the planned block."
    }

    static func clockString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// The planned-vs-actual snapshot captured when a focus session is stopped, driving the completion summary.
private struct FocusSummary: Identifiable {
    let id = UUID()
    let taskId: String
    let title: String
    let planned: Int
    let actual: Int
}
