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
    /// First-run gate: signed-in users who haven't completed onboarding see it once before the shell.
    /// Demo/automation launches bypass it so seeded screenshots land directly in the app.
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    #if DEBUG
    /// Drives the `-sectographGallery` debug picker. Presented as a sheet OVER the shell (not as the
    /// app root) so its Done button can dismiss back to the app — the gallery is never a dead-end.
    @State private var showGallery = AppConfig.isSectographGallery
    #endif

    var body: some View {
        #if DEBUG
        shell
            .sheet(isPresented: $showGallery) {
                NavigationStack { DialStylePicker() }
            }
        #else
        shell
        #endif
    }

    @ViewBuilder private var shell: some View {
        switch auth.state {
        case .unknown:
            SplashView()
        case .signedOut:
            SignInView()
        case .signedIn:
            if AppConfig.isForceOnboarding {
                OnboardingView()
            } else if hasOnboarded || AppConfig.isRunningDemo {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
    }
}

/// The five-tab root (AppSpec §4): Today · Plan · (+) · Lists · Insights. Phase 0 ships Today as a
/// real (thin) screen; the rest are labeled placeholders so the navigation shell exists end-to-end.
struct RootTabView: View {
    /// Tracks the selected tab so the center `+` can present Quick Add instead of "selecting" a tab.
    @Environment(AppServices.self) private var services
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab
    @State private var showQuickAdd = false
    @State private var showFocusDemo = false
    /// Set by onboarding's "Create your first task" so the shell opens Quick Add once on first appear.
    @AppStorage("pendingFirstQuickAdd") private var pendingFirstQuickAdd = false

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
            // Guided first capture: onboarding's "Create your first task" queues this so the shell
            // opens Quick Add once, right after onboarding completes.
            if pendingFirstQuickAdd {
                pendingFirstQuickAdd = false
                showQuickAdd = true
            }
            // Ask for notification permission once the shell is up (reminders + alarm chains need it).
            // The shell only appears after onboarding, so this is now a post-value ask, not cold-launch;
            // it self-guards against headless demo launches so the prompt can't block them.
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
        // Deep links (journey G15-S16): doit://today|plan|lists|insights, doit://quickadd, doit://task/<id>.
        .onOpenURL { handleDeepLink($0) }
        // Widget/Control & Live-Activity actions hand off via the App Group (group.app.doit): a Quick-Add
        // control raises a flag, and Live-Activity pause/stop write a focus command. We pick them up on
        // foreground. (No-op until the App Group entitlement exists — see Widget/README.)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { processWidgetControls() }
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

    /// Route a `doit://` deep link to the right surface (journey G15-S16). Unknown links no-op safely.
    /// Recognized: today · plan · lists · insights (tabs); quickadd/add (capture); task/<id> (open detail).
    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "doit" else { return }
        let host = (url.host ?? "").lowercased()
        switch host {
        case "today": selection = .today
        case "plan": selection = .plan
        case "lists": selection = .lists
        case "insights": selection = .insights
        case "quickadd", "add", "capture": showQuickAdd = true
        case "task":
            // doit://task/<id> — jump to Today and let it present the task detail.
            let id = url.pathComponents.first { $0 != "/" && !$0.isEmpty }
            if let id { services.pendingOpenTaskId = id; selection = .today }
        default: break
        }
    }

    /// Drain any pending widget/Live-Activity commands from the App Group on foreground.
    private func processWidgetControls() {
        guard let defaults = UserDefaults(suiteName: "group.app.doit") else { return }
        if defaults.bool(forKey: "doit.pendingQuickAdd") {
            defaults.set(false, forKey: "doit.pendingQuickAdd")
            showQuickAdd = true
        }
        if let control = defaults.string(forKey: "doit.focusControl") {
            defaults.removeObject(forKey: "doit.focusControl")
            Task { await handleFocusControl(control) }
        }
        let pendingComplete = defaults.stringArray(forKey: "doit.pendingComplete") ?? []
        if !pendingComplete.isEmpty {
            defaults.removeObject(forKey: "doit.pendingComplete")
            Task { await completeFromWidget(pendingComplete) }
        }
    }

    /// Apply task completions a widget queued while the app was backgrounded (CompleteTaskIntent).
    @MainActor private func completeFromWidget(_ ids: [String]) async {
        let mutation = TaskMutation(context: modelContext, engine: services.syncEngine,
                                    clock: services.clock, idGenerator: services.idGenerator)
        for id in ids {
            var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let task = try? modelContext.fetch(descriptor).first, task.status != .done {
                await mutation.toggleComplete(task)
            }
        }
        if AppConfig.isLiveSync { await services.syncOnce() }
    }

    /// Apply a Live-Activity focus command ("toggle:<taskId>" / "stop:<taskId>") to the live session.
    @MainActor private func handleFocusControl(_ control: String) async {
        let action = control.split(separator: ":", maxSplits: 1).first.map(String.init) ?? control
        switch action {
        case "toggle":
            guard let session = services.focus.session else { return }
            session.isRunning ? services.focus.pause() : services.focus.resume()
        case "stop":
            guard let result = services.focus.stop() else { return }
            let taskId = result.taskId
            var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == taskId })
            descriptor.fetchLimit = 1
            if let task = try? modelContext.fetch(descriptor).first {
                await TaskMutation(context: modelContext, engine: services.syncEngine,
                                   clock: services.clock, idGenerator: services.idGenerator)
                    .addActualMinutes(task, result.minutes)
                if AppConfig.isLiveSync { await services.syncOnce() }
            }
        default:
            break
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

