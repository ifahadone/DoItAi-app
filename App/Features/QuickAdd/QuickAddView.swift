import SwiftUI
import SwiftData
import SyncCore
import DesignSystem

/// Glance-first natural-language capture. The common path is type → verify the compact
/// interpretation → add. Full field editing stays one tap away for users who need precision.
struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services

    @State private var input = ""
    @State private var parsed = ParsedQuickAdd(title: "")
    @State private var aiBusy = false
    @State private var isSaving = false
    @State private var saved = false
    @State private var showDetails = false
    @State private var detent: PresentationDetent = .medium
    @State private var dictation = SpeechDictation()
    @State private var dueDraft = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: Date()
    ) ?? Date()
    @FocusState private var captureFocused: Bool

    private let examples = [
        "Call the dentist tomorrow 10am",
        "Finish proposal Friday #work !p1",
        "Buy groceries tonight"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()
                if saved {
                    savedConfirmation
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else {
                    captureContent
                }
            }
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { captureFocused = true }
            .onChange(of: dictation.transcript) { _, newValue in
                guard !newValue.isEmpty else { return }
                input = newValue
                parsed = QuickAddParser.parse(newValue)
            }
            .onDisappear { dictation.stop() }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private var captureContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text("What needs doing?")
                        .font(.title2.weight(.bold))
                    Text("Say it naturally. DoIT will pull out the useful details.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                captureField

                if parsed.title.isEmpty {
                    examplePrompts
                } else {
                    interpretedSummary

                    if showDetails {
                        detailEditor
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    actionArea
                }
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.top, theme.spacing.md)
            .padding(.bottom, theme.spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var captureField: some View {
        HStack(alignment: .bottom, spacing: theme.spacing.sm) {
            TextField("e.g. Finish proposal tomorrow at 9", text: $input, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .focused($captureFocused)
                .submitLabel(.done)
                .onChange(of: input) { _, newValue in
                    parsed = QuickAddParser.parse(newValue)
                }

            if dictation.isAvailable {
                Button { dictation.toggle() } label: {
                    Image(systemName: dictation.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                        .foregroundStyle(dictation.isRecording ? Color.red : theme.colors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Dictate task")
            }
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.md)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.large)
                .strokeBorder(captureFocused ? theme.colors.accent : theme.colors.separator.opacity(0.55),
                              lineWidth: captureFocused ? 1.5 : 1)
        }
        .animation(.easeOut(duration: 0.18), value: captureFocused)
    }

    private var examplePrompts: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            Text("Try one")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(examples, id: \.self) { example in
                Button {
                    withAnimation(.snappy) {
                        input = example
                        parsed = QuickAddParser.parse(example)
                    }
                } label: {
                    HStack {
                        Text(example)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, theme.spacing.xs)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var interpretedSummary: some View {
        VStack(alignment: .leading, spacing: theme.spacing.md) {
            HStack(alignment: .top, spacing: theme.spacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(theme.colors.statusDone)
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(parsed.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if summaryItems.isEmpty {
                        Text("Ready to add to Inbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: theme.spacing.xs) {
                            ForEach(summaryItems) { item in
                                Label(item.label, systemImage: item.icon)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(item.tint)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(item.tint.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if dueTimeIsAmbiguous {
                Label("A day was understood, but not a time. Review details to choose one.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, theme.spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var actionArea: some View {
        VStack(spacing: theme.spacing.sm) {
            Button {
                Task { await create() }
            } label: {
                HStack {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "plus")
                    }
                    Text(isSaving ? "Adding…" : "Add task")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: theme.radii.medium))
            .disabled(parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

            HStack {
                Button {
                    withAnimation(.snappy) {
                        showDetails.toggle()
                        detent = showDetails ? .large : .medium
                    }
                } label: {
                    Label(showDetails ? "Hide details" : "Review details",
                          systemImage: showDetails ? "chevron.up" : "slider.horizontal.3")
                }

                Spacer()

                if services.aiConsentEnabled {
                    Button {
                        Task {
                            aiBusy = true
                            parsed = await services.aiParseOrLocal(input)
                            aiBusy = false
                        }
                    } label: {
                        if aiBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Improve", systemImage: "sparkles")
                        }
                    }
                    .disabled(aiBusy)
                }
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(theme.colors.accent)
        }
    }

    private var detailEditor: some View {
        VStack(spacing: 0) {
            detailRow {
                TextField("Title", text: $parsed.title, axis: .vertical)
            }

            Divider()

            detailRow {
                Toggle("Due date", isOn: Binding(
                    get: { parsed.dueAt != nil },
                    set: { on in parsed.dueAt = on ? dueDraft : nil }
                ))
            }

            if parsed.dueAt != nil {
                Divider()
                detailRow {
                    DatePicker("When", selection: Binding(
                        get: { parsed.dueAt ?? dueDraft },
                        set: { parsed.dueAt = $0; dueDraft = $0 }
                    ))
                }
            }

            Divider()

            detailRow {
                Picker("Priority", selection: $parsed.priority) {
                    Text("None").tag(Priority.none)
                    Text("P1 · Urgent").tag(Priority.p1)
                    Text("P2 · High").tag(Priority.p2)
                    Text("P3 · Medium").tag(Priority.p3)
                    Text("P4 · Low").tag(Priority.p4)
                }
            }

            if !parsed.tagNames.isEmpty {
                Divider()
                detailRow {
                    LabeledContent("Tags") {
                        HStack {
                            ForEach(parsed.tagNames, id: \.self) { TagPill(name: $0) }
                        }
                    }
                }
            }
        }
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.medium))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radii.medium)
                .strokeBorder(theme.colors.separator.opacity(0.45))
        }
    }

    private func detailRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.md)
    }

    private var savedConfirmation: some View {
        VStack(spacing: theme.spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(theme.colors.statusDone)
                .symbolEffect(.bounce, value: saved)
            VStack(spacing: theme.spacing.xs) {
                Text("Added")
                    .font(.title2.weight(.bold))
                Text(parsed.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(theme.spacing.xxl)
    }

    private struct SummaryItem: Identifiable {
        let id: String
        let icon: String
        let label: String
        let tint: Color
    }

    private var summaryItems: [SummaryItem] {
        var items: [SummaryItem] = []
        if let due = parsed.dueAt {
            items.append(SummaryItem(
                id: "due",
                icon: "calendar",
                label: due.formatted(date: .abbreviated, time: .shortened),
                tint: theme.colors.accent
            ))
        }
        if parsed.priority != .none {
            items.append(SummaryItem(
                id: "priority",
                icon: "flag.fill",
                label: "P\(5 - parsed.priority.rawValue)",
                tint: parsed.priority == .p1 ? .red : .orange
            ))
        }
        for tag in parsed.tagNames.prefix(2) {
            items.append(SummaryItem(id: "tag:\(tag)", icon: "number", label: tag, tint: .secondary))
        }
        return items
    }

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
        guard !isSaving else { return }
        isSaving = true
        captureFocused = false
        await services.composeQuickAdd(parsed, ownerId: ownerId)
        await services.syncOnce()
        withAnimation(.snappy) { saved = true }
        try? await Task.sleep(for: .milliseconds(650))
        dismiss()
    }
}

/// Small wrapping layout for compact interpreted-field chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var cursor = CGPoint.zero
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(cursor)
            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, cursor.x - spacing)
        }

        return (
            CGSize(width: min(maxWidth, usedWidth), height: cursor.y + lineHeight),
            points
        )
    }
}
