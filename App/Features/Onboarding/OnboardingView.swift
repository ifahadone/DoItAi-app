import SwiftUI
import DesignSystem

/// First-run onboarding (AppSpec S02 · journey G01), shown once after sign-in and gated by
/// `@AppStorage("hasOnboarded")`. It teaches the core loop across dedicated value pages
/// (Capture → Plan → Execute → Reflect, journey frames G01-S05…S07), captures the AI-consent choice
/// (**off by default**, G01-S08, with a plain explanation that AI always previews before writing),
/// then shows a notification value pre-prompt (G01-S12) *before* requesting OS access — so the system
/// prompt only appears once the user has opted in. Calendar/location permission stay progressive
/// (requested in Plan / at a location reminder), never dumped up front.
struct OnboardingView: View {
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @AppStorage("pendingFirstQuickAdd") private var pendingFirstQuickAdd = false
    @Environment(\.theme) private var theme
    @Environment(AppServices.self) private var services

    @State private var page = 0
    @State private var aiConsent = false
    @State private var requestingNotifications = false
    private let pageCount = 6

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                capture.tag(1)
                plan.tag(2)
                execute.tag(3)
                aiPage.tag(4)
                notifications.tag(5)
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
        page0(title: "Your day, as a dial",
              sub: "DoIT turns tasks into time you can see — on a 24-hour sectograph, an Apple-Calendar-style planner, and home-screen widgets.") {
            SectographDial(items: DialPreviewSample.items, titles: DialPreviewSample.titles, style: .aurora)
                .frame(width: 240, height: 240)
                .accessibilityHidden(true)
        }
    }

    // MARK: Page 1 — Capture (G01-S05)
    private var capture: some View {
        page0(title: "Capture in a second",
              sub: "Type or dictate in plain language — “Call the dentist tomorrow 9am #health !p2”. DoIT parses it into a task you can review before saving.") {
            heroIcon("mic.circle.fill")
        }
    }

    // MARK: Page 2 — Plan & Sectograph (G01-S06)
    private var plan: some View {
        page0(title: "Plan becomes visible time",
              sub: "Drag tasks onto a calendar-style day, or let Auto-plan place them around your meetings. Every block shows up on the dial.") {
            SectographDial(items: DialPreviewSample.items, titles: DialPreviewSample.titles, style: .aurora)
                .frame(width: 200, height: 200)
                .accessibilityHidden(true)
        }
    }

    // MARK: Page 3 — Execute & Reflect (G01-S07)
    private var execute: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xl) {
            Spacer()
            Text("Execute, then reflect")
                .font(.title.bold())
                .frame(maxWidth: .infinity, alignment: .center)
            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                row("timer", "Focus", "Start a block and the dial counts it down. Actual time is logged automatically.")
                row("repeat", "Routines & streaks", "Chain your morning steps and keep habit streaks honest.")
                row("chart.bar.xaxis", "Insights", "See completion, focus time and where your week actually went.")
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

    // MARK: Page 4 — AI consent (opt-in, G01-S08)
    private var aiPage: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()
            heroIcon("sparkles")
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

    // MARK: Page 5 — Notification value pre-prompt (G01-S12)
    private var notifications: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()
            heroIcon("bell.badge.fill")
            VStack(spacing: theme.spacing.sm) {
                Text("Reminders that respect you").font(.title.bold())
                Text("DoIT can nudge you before a task is due and ring routine alarms. It honors Quiet Hours and never spams you. You can turn this on now or later in Settings.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, theme.spacing.xl)
            VStack(spacing: theme.spacing.md) {
                Button {
                    requestingNotifications = true
                    Task {
                        await services.requestNotificationAuthorization()
                        finish(openQuickAdd: true)
                    }
                } label: {
                    Label("Turn on reminders", systemImage: "bell")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(requestingNotifications)

                Button("Not now") { finish(openQuickAdd: true) }
                    .font(.subheadline)
                    .disabled(requestingNotifications)
            }
            .padding(.horizontal, theme.spacing.xl)
            Spacer()
        }
    }

    // MARK: Footer (value/consent pages only; the notification page carries its own CTAs)
    private var footer: some View {
        Group {
            if page < pageCount - 1 {
                Button { withAnimation(.snappy) { page += 1 } } label: {
                    Text("Continue").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, theme.spacing.xl)
                .padding(.bottom, theme.spacing.lg)
            }
        }
    }

    // MARK: Reusable page scaffold (centered hero + title + subtitle)
    private func page0<Hero: View>(title: String, sub: String, @ViewBuilder hero: () -> Hero) -> some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()
            hero()
            VStack(spacing: theme.spacing.sm) {
                Text(title).font(.title.bold())
                Text(sub).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, theme.spacing.xl)
            Spacer()
        }
    }

    private func heroIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 64))
            .foregroundStyle(theme.colors.accent)
            .accessibilityHidden(true)
    }

    /// Persist the AI choice, optionally queue the guided first Quick Add (G01-S09→S11), and dismiss
    /// onboarding by flipping `hasOnboarded` (which routes `RootView` to the tab shell).
    private func finish(openQuickAdd: Bool) {
        let consent = aiConsent
        Task { await services.setAiConsent(consent) }
        pendingFirstQuickAdd = openQuickAdd
        withAnimation(.snappy) { hasOnboarded = true }
    }
}
