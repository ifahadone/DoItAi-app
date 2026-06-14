import SwiftUI
import SwiftData
import DesignSystem

/// The app entry point (AppSpec §4, §7). Builds the shared App-Group SwiftData container, the DI
/// container (``AppServices``), and the auth service, then shows either the sign-in gate or the root
/// tab shell.
///
/// Requires the Xcode app target. This file (and everything under `App/`) does NOT build via
/// `swift build` on the SPM packages — it needs the app target that links SwiftData, SwiftUI, and
/// AuthenticationServices, plus the local `SyncCore` and `DesignSystem` packages. See README.
@main
struct DoITApp: App {
    @State private var auth: AuthService
    @State private var services: AppServices
    private let container: ModelContainer
    /// Retained for the process lifetime: `UNUserNotificationCenter` holds its delegate weakly.
    private let notificationHandler: NotificationActionHandler

    init() {
        let container = PersistenceContainer.makeShared()
        #if DEBUG
        if AppConfig.isUIDemo { DemoData.seed(into: container) }
        #endif
        let auth = AuthService()
        let services = AppServices(container: container, auth: auth)
        self.container = container
        _auth = State(initialValue: auth)
        _services = State(initialValue: services)
        // Install the actionable-notification delegate + Complete/Snooze category (P1-I).
        let handler = NotificationActionHandler(container: container, services: services)
        handler.register()
        self.notificationHandler = handler
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(services)
                .theme(.default)
                .task {
                    await auth.bootstrap()
                }
        }
        .modelContainer(container)
    }
}

/// Switches between the sign-in gate and the main shell based on auth state.
private struct RootView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        #if DEBUG
        if AppConfig.isSectographGallery {
            NavigationStack { DialStylePicker() }
        } else {
            shell
        }
        #else
        shell
        #endif
    }

    @ViewBuilder private var shell: some View {
        switch auth.state {
        case .unknown:
            ProgressView("Loading…")
        case .signedOut:
            SignInView()
        case .signedIn:
            RootTabView()
        }
    }
}

/// The five-tab root (AppSpec §4): Today · Plan · (+) · Lists · Insights. Phase 0 ships Today as a
/// real (thin) screen; the rest are labeled placeholders so the navigation shell exists end-to-end.
struct RootTabView: View {
    /// Tracks the selected tab so the center `+` can present Quick Add instead of "selecting" a tab.
    @Environment(AppServices.self) private var services
    @Environment(AuthService.self) private var auth
    @State private var selection: Tab
    @State private var showQuickAdd = false
    @State private var showFocusDemo = false

    enum Tab: Hashable { case today, plan, add, lists, insights }

    init() {
        let tab: Tab
        switch AppConfig.startTab {
        case "plan": tab = .plan
        case "lists": tab = .lists
        case "insights": tab = .insights
        default: tab = .today
        }
        _selection = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)

            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(Tab.plan)

            // Center Quick Add: AppSpec §4 describes a floating capture button. Phase 0 uses a tab
            // slot as the entry point; a true FAB overlay is a Phase 1 polish item.
            Color.clear
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(Tab.add)

            ListsView()
                .tabItem { Label("Lists", systemImage: "tray.full") }
                .tag(Tab.lists)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar") }
                .tag(Tab.insights)
        }
        .task {
            // Rehydrate any unsynced outbox + pull cursor from a previous run BEFORE the first sync,
            // so offline edits made before an app kill still flush (AppSpec §8).
            await services.bootstrapPersistedState()
            // Live-sync (`-liveSync`): initial flush + pull when the shell appears, so the app shows
            // what's already on the server. TODO(Phase 1): trigger on foreground + after each mutation
            // for all signed-in sessions (not just the dev demo mode).
            if AppConfig.isLiveSync { await services.syncOnce() }
            await services.publishAgenda() // refresh the agenda widget snapshot (P1-J)
            // Ask for notification permission once the shell is up (reminders + alarm chains need it);
            // self-guards against headless demo launches so the prompt can't block them.
            await services.requestNotificationAuthorizationIfNeeded()
            // Refresh the Pro entitlement from the server (the authority for feature gates, P6-4).
            await services.entitlements.refresh()
            // Open the realtime socket (P5-5): a collaborator's `sync.bump` triggers an immediate pull.
            // Self-guards demo launches; a dropped socket falls back to the foreground/interval pull.
            if AppConfig.isLiveSync { await services.connectRealtime() }
            // Mirror scheduled blocks to Apple Calendar when the user enabled it in Settings (P3-7).
            if UserDefaults.standard.bool(forKey: "calendarWriteBackEnabled") && !AppConfig.isRunningDemo {
                _ = await services.exportToCalendar()
            }
            #if DEBUG
            // `-livePushDemo`: prove app→server by creating + flushing one task via the real path.
            if AppConfig.isLivePushDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.livePushDemo(ownerId: userId)
            }
            // `-liveCrudDemo`: exercise the real TaskMutation path (priority + complete) against live.
            if AppConfig.isLiveCrudDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveCrudDemo(ownerId: userId)
            }
            // `-seedDemo`: wipe + seed a realistic day (lists + scheduled tasks + due markers).
            if AppConfig.isSeedDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.seedDemoData(ownerId: userId)
            }
            // `-liveListDemo`: create list + tag + assigned task via the real mutation paths.
            if AppConfig.isLiveListDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveListDemo(ownerId: userId)
            }
            // `-liveQuickAddDemo`: parse an NL phrase and compose it into a task (P1-H).
            if AppConfig.isLiveQuickAddDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveQuickAddDemo(ownerId: userId)
            }
            // `-liveReminderDemo`: insert 70 reminders + run the 64-cap scheduler (P1-I).
            if AppConfig.isLiveReminderDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveReminderDemo(ownerId: userId)
            }
            // `-liveFocusDemo`: log actualMinutes + start a live focus session, then show the timer (P2-4).
            if AppConfig.isLiveFocusDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveFocusDemo(ownerId: userId)
                showFocusDemo = true
            }
            // `-liveRoutineDemo`: create a daily routine + materialize today's instances (P3-3).
            if AppConfig.isLiveRoutineDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveRoutineDemo(ownerId: userId)
            }
            // `-liveHabitDemo`: create a habit + log it via /habits/log (P3-4).
            if AppConfig.isLiveHabitDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveHabitDemo(ownerId: userId)
            }
            // `-liveAlarmDemo`: routine alarm chain + explicit alarm + 64-cap scheduler (P3-6).
            if AppConfig.isLiveAlarmDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveAlarmDemo(ownerId: userId)
            }
            // `-liveLocationDemo`: geofenced reminder syncs region to server + region monitoring (P3-7).
            if AppConfig.isLiveLocationDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveLocationDemo(ownerId: userId)
            }
            // `-liveCalendarDemo`: calendar write-back diff + EventKit apply (device-bound) (P3-7).
            if AppConfig.isLiveCalendarDemo, case let .signedIn(userId) = auth.state, let userId {
                await services.liveCalendarDemo(ownerId: userId)
            }
            #endif
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .add {
                showQuickAdd = true
                selection = .today // bounce back; the + is an action, not a destination
            }
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView()
                .environment(auth)
                .environment(services)
        }
        .sheet(isPresented: $showFocusDemo) {
            FocusTimerView().environment(services)
        }
    }
}

/// A simple labeled placeholder for the not-yet-built tabs.
private struct PlaceholderView: View {
    let title: String
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming in a later phase."))
                .navigationTitle(title)
        }
    }
}

