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
            Button {
                Task { planning = true; applied = false; proposal = await services.aiAutoPlan(intent: trimmed(intent)); planning = false }
            } label: {
                HStack {
                    Label("Propose a plan", systemImage: "wand.and.stars")
                    Spacer()
                    if planning { ProgressView().controlSize(.small) }
                }
            }
            .disabled(planning)

            if let proposal {
                ForEach(proposal.blocks) { block in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.title)
                        Text("\(timeRange(block)) · \(block.reason)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(proposal.unscheduled) { item in
                    Label("\(item.title) — \(item.reason)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !proposal.blocks.isEmpty && !applied {
                    let blocks = proposal.blocks
                    Button {
                        Task { await services.applyPlan(blocks); applied = true }
                    } label: {
                        Label("Apply plan", systemImage: "checkmark.circle")
                    }
                }
                if applied { Label("Plan applied to your day", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        } header: {
            Text("Auto-plan")
        } footer: {
            Text("AI ranks your open tasks by your intent; a deterministic solver places them into free slots.")
        }
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
