import SwiftUI
import SyncCore

/// The AI assistant surface (AppSpec §5.10, DevelopmentPlan P4-8): a streamed morning brief, an
/// auto-plan proposal you accept/edit, and a streamed weekly review. Everything degrades gracefully —
/// with AI off or unreachable, the actions no-op and the rest of the app keeps working.
struct AIAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @State private var briefText = ""
    @State private var briefing = false
    @State private var reviewText = ""
    @State private var reviewing = false

    @State private var intent = ""
    @State private var proposal: AIScheduleProposal?
    @State private var planning = false
    @State private var applied = false
    /// Blocks the user has kept in the proposal review (journey G05-S13) — nothing is written until
    /// "Apply" and only these survive. Defaults to every proposed block; the user can drop any.
    @State private var keptBlockIds: Set<String> = []
    // Auto-plan preferences / constraints (journey G05-S11): working hours + inter-block buffer.
    @State private var bufferMinutes = 10
    @State private var workStart = 9
    @State private var workEnd = 18
    @State private var showPrefs = false

    var body: some View {
        NavigationStack {
            Form {
                if !services.aiConsentEnabled {
                    Section {
                        Label("Turn on the AI assistant in Settings to use briefs, auto-plan, and reviews.",
                              systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    briefSection
                    autoPlanSection
                    reviewSection
                }
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var briefSection: some View {
        Section("Morning Brief") {
            if briefText.isEmpty && !briefing {
                Button { streamBrief() } label: { Label("Generate today's brief", systemImage: "sun.max") }
            } else {
                Text(briefText.isEmpty ? "…" : briefText)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if briefing { ProgressView().controlSize(.small) }
            }
        }
    }

    private var autoPlanSection: some View {
        Section {
            TextField("Intent — e.g. mornings for deep work", text: $intent)
            DisclosureGroup("Preferences & constraints", isExpanded: $showPrefs) {
                Stepper("Day starts \(hourLabel(workStart))", value: $workStart, in: 0...22)
                Stepper("Day ends \(hourLabel(workEnd))", value: $workEnd, in: 1...24)
                Stepper("Buffer between blocks: \(bufferMinutes)m", value: $bufferMinutes, in: 0...60, step: 5)
            }
            Button { propose() } label: {
                HStack {
                    Label(proposal == nil ? "Propose a plan" : "Regenerate", systemImage: "wand.and.stars")
                    Spacer()
                    if planning { ProgressView().controlSize(.small) }
                }
            }
            .disabled(planning)

            if let proposal {
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
                    }
                    .buttonStyle(.plain)
                    .disabled(applied)
                }
                ForEach(proposal.unscheduled) { item in
                    Label("\(item.title) — \(item.reason)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !applied {
                    let kept = proposal.blocks.filter { keptBlockIds.contains($0.id) }
                    Button {
                        Task { await services.applyPlan(kept); applied = true }
                    } label: {
                        Label(kept.isEmpty ? "Select at least one block" : "Apply \(kept.count) block\(kept.count == 1 ? "" : "s")",
                              systemImage: "checkmark.circle")
                    }
                    .disabled(kept.isEmpty)
                    Button(role: .destructive) { discardProposal() } label: {
                        Label("Discard proposal", systemImage: "xmark.circle")
                    }
                }
                if applied { Label("Plan applied to your day", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        } header: {
            Text("Auto-plan")
        } footer: {
            Text("AI ranks your open tasks by your intent; a deterministic solver places them into free slots. Nothing changes until you Apply.")
        }
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
        Section("Weekly Review") {
            if reviewText.isEmpty && !reviewing {
                Button { streamReview() } label: { Label("Generate weekly review", systemImage: "chart.line.uptrend.xyaxis") }
            } else {
                Text(reviewText.isEmpty ? "…" : reviewText)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if reviewing { ProgressView().controlSize(.small) }
            }
        }
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
