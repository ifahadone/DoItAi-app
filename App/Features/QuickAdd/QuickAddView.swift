import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Natural-language quick capture (AppSpec §5.10, DevelopmentPlan P1-H). Type a phrase like
/// "Lunch with Sam tomorrow 1pm #work !p1"; ``QuickAddParser`` (on-device, NSDataDetector) extracts
/// title/due/tags/priority into a live preview before you save. Cloud-AI parsing is a Phase-4 surface.
struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services

    @State private var input = ""
    @State private var parsed = ParsedQuickAdd(title: "")
    @State private var aiBusy = false
    /// Live voice dictation into the NL field (FR-QADD-080).
    @State private var dictation = SpeechDictation()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        TextField("e.g. Lunch with Sam tomorrow 1pm #work !p1", text: $input, axis: .vertical)
                            .lineLimit(1...3)
                            .onChange(of: input) { _, newValue in parsed = QuickAddParser.parse(newValue) }
                        if dictation.isAvailable {
                            Button { dictation.toggle() } label: {
                                Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                                    .foregroundStyle(dictation.isRecording ? Color.red : Color.accentColor)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Dictate task")
                        }
                    }
                    if services.aiConsentEnabled {
                        Button {
                            Task { aiBusy = true; parsed = await services.aiParseOrLocal(input); aiBusy = false }
                        } label: {
                            HStack {
                                Label("Parse with AI", systemImage: "sparkles")
                                Spacer()
                                if aiBusy { ProgressView() }
                            }
                        }
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || aiBusy)
                    }
                } footer: {
                    Text("#tag for tags · !p1–!p4 for priority · natural dates like \"tomorrow 9am\".")
                }

                if !parsed.title.isEmpty {
                    Section("Preview") {
                        LabeledContent("Title", value: parsed.title)
                        if let due = parsed.dueAt {
                            LabeledContent("Due", value: due.formatted(date: .abbreviated, time: .shortened))
                        }
                        if parsed.priority != .none {
                            LabeledContent("Priority") { PriorityChip(level: parsed.priority.rawValue) }
                        }
                        if !parsed.tagNames.isEmpty {
                            LabeledContent("Tags") {
                                HStack { ForEach(parsed.tagNames, id: \.self) { TagPill(name: $0) } }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: dictation.transcript) { _, newValue in
                guard !newValue.isEmpty else { return }
                input = newValue
                parsed = QuickAddParser.parse(newValue)
            }
            .onDisappear { dictation.stop() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await create() } }.disabled(parsed.title.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var ownerId: String {
        if case let .signedIn(userId) = auth.state, let userId { return userId }
        return "local-user"
    }

    private func create() async {
        await services.composeQuickAdd(parsed, ownerId: ownerId)
        if AppConfig.isLiveSync { await services.syncOnce() }
        dismiss()
    }
}
