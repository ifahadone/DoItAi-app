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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Lunch with Sam tomorrow 1pm #work !p1", text: $input, axis: .vertical)
                        .lineLimit(1...3)
                        .onChange(of: input) { _, newValue in parsed = QuickAddParser.parse(newValue) }
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
