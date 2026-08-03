import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// The AI assistant surface (AppSpec §5.10, DevelopmentPlan P4-8): a streamed morning brief, an
/// auto-plan proposal you accept/edit, and a structured + streamed weekly review. Everything degrades
/// gracefully — with AI off or unreachable, the actions no-op and the rest of the app keeps working.
struct AIAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(AppServices.self) private var services
    var onViewToday: () -> Void = {}

    /// Non-deleted tasks, for the deterministic weekly-review metrics (journey G12-S10).
    @Query(filter: #Predicate<TaskModel> { $0.deletedAt == nil && !$0.archived })
    private var tasks: [TaskModel]

    @State private var briefText = ""
    @State private var briefing = false
    @State private var reviewText = ""
    @State private var reviewing = false

    @State private var intent = ""
    @State private var proposal: AIScheduleProposal?
    @State private var planning = false
    @State private var applied = false
    /// Prior schedules captured when the plan was applied, enabling Undo (journey G05-S15).
    @State private var planUndo: [AppServices.PlanScheduleSnapshot] = []
    /// Blocks the user has kept in the proposal review (journey G05-S13) — nothing is written until
    /// "Apply" and only these survive. Defaults to every proposed block; the user can drop any.
    @State private var keptBlockIds: Set<String> = []
    // Auto-plan preferences / constraints (journey G05-S11): working hours + inter-block buffer.
    @State private var bufferMinutes = 10
    @State private var workStart = 9
    @State private var workEnd = 18
    @State private var showPrefs = false
    @State private var activeTool: Tool = .plan

    private enum Tool: String, CaseIterable, Identifiable {
        case brief = "Brief"
        case plan = "Plan"
        case review = "Review"
        var id: String { rawValue }
        var subtitle: String {
            switch self {
            case .brief: return "Orient your day"
            case .plan: return "Fit work into time"
            case .review: return "Learn from your week"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.xl) {
                    assistantHeader
                        .doitEntrance(order: 0)

                    if !services.aiConsentEnabled {
                        consentCallout
                            .doitEntrance(order: 1)
                    } else {
                        Picker("Assistant tool", selection: $activeTool) {
                            ForEach(Tool.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .doitEntrance(order: 1)

                        Group {
                            switch activeTool {
                            case .brief: briefSection
                            case .plan: autoPlanSection
                            case .review: reviewSection
                            }
                        }
                        .id(activeTool)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .doitEntrance(order: 2, trigger: activeTool.rawValue)
                    }
                }
                .padding(.horizontal, theme.spacing.xl)
                .padding(.top, theme.spacing.md)
                .padding(.bottom, theme.spacing.xxl)
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .animation(.spring(response: 0.38, dampingFraction: 0.88), value: activeTool)
        }
    }

    private var assistantHeader: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(theme.colors.accent)
            Text("What would help?")
                .font(.title2.bold())
            Text(services.aiConsentEnabled ? activeTool.subtitle : "AI is optional and every change is previewed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }

    private var consentCallout: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Label("AI assistance is off", systemImage: "lock.shield")
                    .font(.headline)
                Text("DoIT sends task titles, dates, list names and completion status only. Notes, locations and calendar details stay private.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await services.setAiConsent(true) }
            } label: {
                Label("Enable AI assistance", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            Text("Capture and planning still work on-device when AI is off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(theme.spacing.lg)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))
    }

    private var briefSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            DoITSectionHeading("Today’s brief", subtitle: "Due work, conflicts and one suggested focus.")
            if briefText.isEmpty && !briefing {
                Button { streamBrief() } label: {
                    Label("Generate brief", systemImage: "sun.max")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            } else {
                VStack(alignment: .leading, spacing: theme.spacing.md) {
                    Text(briefText.isEmpty ? "Building your brief…" : briefText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        if briefing { ProgressView().controlSize(.small) }
                        Spacer()
                        if !briefing {
                            Button("Refresh") { streamBrief() }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(theme.spacing.lg)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var autoPlanSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            DoITSectionHeading("Auto-plan", subtitle: "Rank open tasks, then place them with deterministic rules.")

            TextField("Intent — e.g. mornings for deep work", text: $intent)
                .padding(theme.spacing.md)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radii.medium)
                        .strokeBorder(theme.colors.separator.opacity(0.5))
                }

            DisclosureGroup("Preferences & constraints", isExpanded: $showPrefs) {
                VStack(spacing: theme.spacing.md) {
                    Stepper("Day starts \(hourLabel(workStart))", value: $workStart, in: 0...22)
                    Stepper("Day ends \(hourLabel(workEnd))", value: $workEnd, in: 1...24)
                    Stepper("Buffer: \(bufferMinutes)m", value: $bufferMinutes, in: 0...60, step: 5)
                }
                .padding(.top, theme.spacing.md)
            }
            .padding(theme.spacing.md)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.medium))

            Button { propose() } label: {
                HStack {
                    Label(proposal == nil ? "Propose a plan" : "Regenerate", systemImage: "wand.and.stars")
                        Spacer()
                    if planning { ProgressView().controlSize(.small) }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(planning)

            if let proposal {
                Divider()
                DoITSectionHeading(
                    "Review the proposal",
                    subtitle: "\(proposal.blocks.count) placed · \(proposal.unscheduled.count) need attention"
                )
                // Review before any write (US-PLAN-030): each placement can be kept or dropped; only
                // kept blocks are committed on Apply. Tap a row to toggle it.
                ForEach(proposal.blocks) { block in
                    Button { toggleBlock(block.id) } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: keptBlockIds.contains(block.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(keptBlockIds.contains(block.id) ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(block.title).foregroundStyle(.primary)
                                    .strikethrough(!keptBlockIds.contains(block.id))
                                Text("\(timeRange(block)) · \(block.reason)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, theme.spacing.xs)
                    }
                    .buttonStyle(.plain)
                    .disabled(applied)
                }
                // Impossible / overbooked plan (G05-S16): nothing fit at all. Point at the levers.
                if proposal.blocks.isEmpty && !proposal.unscheduled.isEmpty {
                    Label("Nothing fit in your free time. Widen your working hours or lower the buffer in Preferences above, or shorten a task below.",
                          systemImage: "exclamationmark.octagon.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(proposal.unscheduled) { item in
                    // Couldn't-fit reasons are actionable (G05-S14): open the task to shorten it, move its
                    // deadline, or schedule it manually.
                    if let task = tasks.first(where: { $0.id == item.taskId }) {
                        NavigationLink {
                            TaskDetailView(task: task).environment(services)
                        } label: {
                            Label("\(item.title) — \(item.reason)", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Label("\(item.title) — \(item.reason)", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !applied {
                    let kept = proposal.blocks.filter { keptBlockIds.contains($0.id) }
                    Button {
                        Task { planUndo = await services.applyPlan(kept); applied = true }
                    } label: {
                        Label(kept.isEmpty ? "Select at least one block" : "Apply \(kept.count) block\(kept.count == 1 ? "" : "s")",
                              systemImage: "checkmark.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(kept.isEmpty)
                    Button(role: .destructive) { discardProposal() } label: {
                        Label("Discard proposal", systemImage: "xmark.circle")
                    }
                } else {
                    // Plan accepted (G05-S15): confirm + offer to view it on Today, or undo the changes.
                    Label("Plan applied to your day", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: applied)
                    Button {
                        dismiss()
                        onViewToday()
                    } label: {
                        Label("View on Today", systemImage: "calendar.day.timeline.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(role: .destructive) {
                        Task { await services.undoPlan(planUndo); planUndo = []; applied = false }
                    } label: { Label("Undo plan", systemImage: "arrow.uturn.backward") }
                }
            }
            Text("AI ranks your open tasks by your intent; a deterministic solver places them into free slots. Nothing changes until you Apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: proposal?.blocks.count)
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: applied)
    }

    private func propose() {
        Task {
            planning = true; applied = false
            let result = await services.aiAutoPlan(intent: trimmed(intent), bufferMinutes: bufferMinutes,
                                                   workStartHour: workStart, workEndHour: workEnd)
            proposal = result
            keptBlockIds = Set(result?.blocks.map(\.id) ?? [])
            planning = false
        }
    }

    private func toggleBlock(_ id: String) {
        if keptBlockIds.contains(id) { keptBlockIds.remove(id) } else { keptBlockIds.insert(id) }
    }

    private func discardProposal() {
        proposal = nil; keptBlockIds = []; applied = false
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.lg) {
            DoITSectionHeading("Weekly review", subtitle: "Metrics stay on-device; AI adds the narrative.")
            // Deterministic at-a-glance metrics (journey G12-S10) — always shown, no AI required, so the
            // numbers are trustworthy; the AI narrative below adds qualitative interpretation.
            let m = weeklyMetrics
            HStack(spacing: 0) {
                reviewMetric("\(m.completed)/\(m.created)", "Completed")
                Divider().frame(height: 34)
                reviewMetric(m.completionRatePct.map { "\($0)%" } ?? "—", "Rate")
                Divider().frame(height: 34)
                reviewMetric(focusLabel(m.focusMinutes), "Focused")
                Divider().frame(height: 34)
                reviewMetric("\(m.overdue)", "Overdue")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing.lg)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))

            if reviewText.isEmpty && !reviewing {
                Button { streamReview() } label: {
                    Label("Generate review", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text(reviewText.isEmpty ? "…" : reviewText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(theme.spacing.lg)
                    .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))
                if reviewing { ProgressView().controlSize(.small) }
            }
            Text("Last 7 days. Metrics are computed on-device; the narrative is AI-generated.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func reviewMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Deterministic last-7-day metrics from local data, reusing the shared ``Analytics`` engine.
    private var weeklyMetrics: (created: Int, completed: Int, overdue: Int, completionRatePct: Int?, focusMinutes: Int) {
        let now = services.clock.now()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let interval = DateInterval(start: start, end: now)
        let stats = tasks.map { t in
            TaskStat(id: t.id, isDone: t.status == .done, createdAt: t.createdAt, dueAt: t.dueAt,
                     completedAt: t.completedAt, scheduledStart: t.scheduledStart, scheduledEnd: t.scheduledEnd,
                     actualMinutes: t.actualMinutes, listId: t.listId)
        }
        let c = Analytics.completion(stats, in: interval, now: now)
        let recent = stats.filter { ($0.completedAt.map { interval.contains($0) }) ?? false }
        let focus = Analytics.focus(recent)
        return (c.created, c.completed, c.overdue, c.completionRatePct, focus.totalMinutes)
    }

    private func focusLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }

    // MARK: - Streaming

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

    private func streamReview() {
        Task {
            reviewing = true
            reviewText = ""
            do {
                for try await event in await services.reviewStream() {
                    if case let .text(delta) = event { reviewText += delta }
                }
            } catch {
                if reviewText.isEmpty { reviewText = "Couldn't generate a review right now." }
            }
            reviewing = false
        }
    }

    private func hourLabel(_ h: Int) -> String {
        var comps = DateComponents(); comps.hour = h % 24
        let date = Calendar.current.date(from: comps) ?? Date()
        let formatter = DateFormatter(); formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }

    private func trimmed(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func timeRange(_ block: AIProposedBlock) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let out = DateFormatter()
        out.timeStyle = .short
        guard let start = parser.date(from: block.startIso), let end = parser.date(from: block.endIso) else {
            return ""
        }
        return "\(out.string(from: start))–\(out.string(from: end))"
    }
}
