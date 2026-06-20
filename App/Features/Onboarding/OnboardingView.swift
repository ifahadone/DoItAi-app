import SwiftUI
import DesignSystem

/// First-run onboarding (AppSpec S02), shown once after sign-in and gated by `@AppStorage("hasOnboarded")`.
/// It teaches the core loop (Capture → Plan → Execute → Reflect), captures the AI-consent choice
/// (**off by default**, with a plain explanation of what AI does and that it always previews before
/// writing), and nudges the first task. OS permissions are requested progressively *after* this —
/// notifications when the tab shell appears, calendar in Plan, location at a location reminder — never
/// dumped up front here.
struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("pendingFirstQuickAdd") private var pendingFirstQuickAdd = false
    @Environment(\.theme) private var theme
    @Environment(AppServices.self) private var services

    @State private var page = 0
    @State private var aiConsent = false
    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                loop.tag(1)
                aiPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .animation(.snappy, value: page)

            footer
        }
        .background(theme.colors.background.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            // Always-visible escape hatch: skip the whole intro from any page.
            Button("Skip") { finish(openQuickAdd: false) }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, theme.spacing.lg)
                .padding(.top, theme.spacing.sm)
                .accessibilityLabel("Skip onboarding")
        }
    }

    // MARK: Page 0 — the dial hero
    private var welcome: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()
            SectographDial(items: DialPreviewSample.items, titles: DialPreviewSample.titles, style: .aurora)
                .frame(width: 240, height: 240)
                .accessibilityHidden(true)
            VStack(spacing: theme.spacing.sm) {
                Text("Your day, as a dial").font(.title.bold())
                Text("DoIT turns tasks into time you can see — on a 24-hour sectograph, an Apple-Calendar-style planner, and home-screen widgets.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, theme.spacing.xl)
            Spacer()
        }
    }

    // MARK: Page 1 — the loop
    private var loop: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            Spacer()
            Text("One simple loop")
                .font(.title.bold())
                .frame(maxWidth: .infinity, alignment: .center)
            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                row("square.and.pencil", "Capture", "Type or dictate — DoIT parses it into a task.")
                row("calendar", "Plan", "Drag tasks into your day, or let Auto-plan place them.")
                row("timer", "Execute", "Start Focus and the dial counts the block down.")
                row("chart.bar", "Reflect", "Insights show where your time actually went.")
            }
            .padding(.horizontal, theme.spacing.xl)
            Spacer()
        }
    }

    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(theme.colors.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(sub).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Page 2 — AI consent (opt-in)
    private var aiPage: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(theme.colors.accent)
            VStack(spacing: theme.spacing.sm) {
                Text("AI, on your terms").font(.title.bold())
                Text("Turn on AI to parse what you capture, propose schedules, and write a weekly review. It always shows a preview — you confirm before anything is written. Off by default; change it anytime in Settings.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, theme.spacing.xl)
            Toggle("Enable AI features", isOn: $aiConsent)
                .padding(.horizontal, theme.spacing.xl)
                .padding(.top, theme.spacing.sm)
            Spacer()
        }
    }

    // MARK: Footer
    private var footer: some View {
        VStack(spacing: theme.spacing.md) {
            if page < pageCount - 1 {
                Button { withAnimation(.snappy) { page += 1 } } label: {
                    Text("Continue").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { finish(openQuickAdd: true) } label: {
                    Label("Create your first task", systemImage: "plus")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                Button("Maybe later") { finish(openQuickAdd: false) }
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, theme.spacing.xl)
        .padding(.bottom, theme.spacing.lg)
    }

    /// Persist the AI choice, optionally queue the guided first Quick Add, and dismiss onboarding by
    /// flipping `hasOnboarded` (which routes `RootView` to the tab shell).
    private func finish(openQuickAdd: Bool) {
        let consent = aiConsent
        Task { await services.setAiConsent(consent) }
        pendingFirstQuickAdd = openQuickAdd
        withAnimation(.snappy) { hasOnboarded = true }
    }
}
