import SwiftUI
import DesignSystem

/// Four-step activation journey: orient, demonstrate capture, connect planning to action, then let
/// the user choose optional capabilities. Permissions stay contextual and both AI and notifications
/// remain off unless explicitly selected.
struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("pendingFirstQuickAdd") private var pendingFirstQuickAdd = false
    @Environment(\.theme) private var theme
    @Environment(AppServices.self) private var services

    @State private var page = 0
    @State private var aiConsent = false
    @State private var notificationsWanted = false
    @State private var finishing = false
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, theme.spacing.xl)
                .padding(.top, theme.spacing.sm)

            TabView(selection: $page) {
                welcome.tag(0)
                capture.tag(1)
                planAndDo.tag(2)
                ready.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if page < pageCount - 1 {
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { page += 1 }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: theme.radii.medium))
                .padding(.horizontal, theme.spacing.xl)
                .padding(.bottom, theme.spacing.lg)
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button("Skip") { finish(openQuickAdd: false) }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, theme.spacing.lg)
                .padding(.top, 44)
                .accessibilityLabel("Skip onboarding")
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index <= page ? theme.colors.accent : theme.colors.separator.opacity(0.55))
                    .frame(height: 4)
            }
        }
        .animation(.easeOut(duration: 0.22), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page + 1) of \(pageCount)")
    }

    private var welcome: some View {
        pageScaffold(
            eyebrow: "YOUR DAY, CLEARLY",
            title: "See what matters now",
            subtitle: "A live day dial, the next action, and your full plan when you want it."
        ) {
            SectographDial(items: DialPreviewSample.items, titles: DialPreviewSample.titles, style: .aurora)
                .frame(width: 252, height: 252)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                .accessibilityHidden(true)
                .doitEntrance(order: 0, trigger: page)
        }
    }

    private var capture: some View {
        pageScaffold(
            eyebrow: "ONE THOUGHT IN",
            title: "A ready task out",
            subtitle: "Type or speak naturally. Add immediately, or open the details only when needed."
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.md) {
                HStack {
                    Text("Finish proposal tomorrow at 9")
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "mic.circle.fill")
                        .foregroundStyle(theme.colors.accent)
                }
                .padding(theme.spacing.lg)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radii.large)
                        .strokeBorder(theme.colors.accent.opacity(0.65))
                }

                HStack(spacing: theme.spacing.sm) {
                    Label("Tomorrow, 9:00 AM", systemImage: "calendar")
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.colors.statusDone)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
                .padding(.horizontal, theme.spacing.xs)
            }
            .padding(.horizontal, theme.spacing.xl)
            .doitEntrance(order: 0, trigger: page)
        }
    }

    private var planAndDo: some View {
        pageScaffold(
            eyebrow: "PLAN, THEN DO",
            title: "Move through the day",
            subtitle: "Place work around your calendar, start Focus, and learn from the time you actually used."
        ) {
            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                capabilityRow("calendar.day.timeline.left", "Plan", "Drag a task into a free time.")
                capabilityRow("timer", "Focus", "Run the block without losing context.")
                capabilityRow("chart.bar.xaxis", "Reflect", "See completion, time and routines.")
            }
            .padding(.horizontal, theme.spacing.xl)
            .doitEntrance(order: 0, trigger: page)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            Spacer()

            VStack(alignment: .leading, spacing: theme.spacing.sm) {
                Text("READY WHEN YOU ARE")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.accent)
                Text("Choose how DoIT helps")
                    .font(.largeTitle.bold())
                Text("Both options can be changed later. Core capture and planning always work offline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .doitEntrance(order: 0, trigger: page)

            VStack(spacing: 0) {
                preferenceRow(
                    icon: "sparkles",
                    title: "AI assistance",
                    detail: "Improves capture, planning and reviews.",
                    isOn: $aiConsent
                )
                Divider().padding(.leading, 54)
                preferenceRow(
                    icon: "bell.badge",
                    title: "Reminders",
                    detail: "Asks iOS for notification access next.",
                    isOn: $notificationsWanted
                )
            }
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radii.large))
            .doitEntrance(order: 1, trigger: page)

            Spacer()

            Button {
                completeOnboarding()
            } label: {
                HStack {
                    if finishing { ProgressView().tint(.white) }
                    Text(finishing ? "Getting things ready…" : "Add my first task")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: theme.radii.medium))
            .disabled(finishing)
            .doitEntrance(order: 2, trigger: page)
        }
        .padding(.horizontal, theme.spacing.xl)
        .padding(.bottom, theme.spacing.lg)
    }

    private func pageScaffold<Hero: View>(
        eyebrow: String,
        title: String,
        subtitle: String,
        @ViewBuilder hero: () -> Hero
    ) -> some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()
            hero()
            VStack(spacing: theme.spacing.sm) {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.accent)
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, theme.spacing.xl)
            .doitEntrance(order: 1, trigger: page)
            Spacer()
        }
    }

    private func capabilityRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(theme.colors.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func preferenceRow(
        icon: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(theme.colors.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden()
        }
        .padding(theme.spacing.lg)
    }

    private func completeOnboarding() {
        guard !finishing else { return }
        finishing = true
        Task {
            await services.setAiConsent(aiConsent)
            if notificationsWanted {
                await services.requestNotificationAuthorization()
            }
            pendingFirstQuickAdd = true
            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                hasOnboarded = true
            }
        }
    }

    private func finish(openQuickAdd: Bool) {
        Task { await services.setAiConsent(aiConsent) }
        pendingFirstQuickAdd = openQuickAdd
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            hasOnboarded = true
        }
    }
}
