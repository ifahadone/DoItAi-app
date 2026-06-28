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
    /// Backing date for the editable due picker when the user adds a due date manually (G03-S06).
    @State private var dueDraft = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()

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
                    Section {
                        // Editable preview (US-CAP-010): every parsed field is correctable before save.
                        TextField("Title", text: $parsed.title, axis: .vertical)

                        Toggle("Due date", isOn: Binding(
                            get: { parsed.dueAt != nil },
                            set: { on in parsed.dueAt = on ? dueDraft : nil }
                        ))
                        if parsed.dueAt != nil {
                            DatePicker("Due", selection: Binding(
                                get: { parsed.dueAt ?? dueDraft },
                                set: { parsed.dueAt = $0; dueDraft = $0 }
                            ))
                            if dueTimeIsAmbiguous {
                                Label("Time not specified — defaulting to midnight. Set a time if needed.",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }

                        Picker("Priority", selection: $parsed.priority) {
                            Text("None").tag(Priority.none)
                            Text("P1").tag(Priority.p1)
                            Text("P2").tag(Priority.p2)
                            Text("P3").tag(Priority.p3)
                            Text("P4").tag(Priority.p4)
                        }

                        if !parsed.tagNames.isEmpty {
                            LabeledContent("Tags") {
                                HStack { ForEach(parsed.tagNames, id: \.self) { TagPill(name: $0) } }
                            }
                        }
                    } header: {
                        Text("Preview")
                    } footer: {
                        Text("AI and local parsing fill these in — correct anything before saving.")
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

    /// A parsed due date sitting exactly on midnight usually means a day was understood but no time
    /// (US-CAP-030): flag it so the user can disambiguate rather than silently scheduling at 00:00.
    private var dueTimeIsAmbiguous: Bool {
        guard let due = parsed.dueAt else { return false }
        let c = Calendar.current.dateComponents([.hour, .minute], from: due)
        return (c.hour ?? 0) == 0 && (c.minute ?? 0) == 0
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
