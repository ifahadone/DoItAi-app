import Foundation
import SwiftData
import SyncCore

/// The app's dependency-injection container (AppSpec §7 "DI container").
///
/// Constructs and holds the long-lived services — the deterministic ``Clock``, the ``IDGenerator``,
/// the ``DefaultSyncEngine`` (with its SwiftData-backed ``SyncStore``), and the ``APIClient`` — and
/// wires them together. Injected into the SwiftUI environment so views/features resolve dependencies
/// without singletons. `@Observable` so future reactive service state can drive the UI.
///
/// Requires the Xcode app target (SwiftData / APIClient). Not part of the SPM packages.
@Observable
@MainActor
final class AppServices {
    let clock: Clock
    let idGenerator: IDGenerator
    let syncEngine: DefaultSyncEngine
    let apiClient: APIClient
    let auth: AuthService
    /// The running focus-timer session (P2-4).
    let focus: FocusController
    /// Read-only EventKit calendar access for the free/busy overlay (P2-5).
    let calendar = CalendarService()
    /// The single Pro-entitlement gate (P6-4); server-validated, drives the StoreKit paywall.
    let entitlements: Entitlements

    private let container: ModelContainer
    /// The durable outbox/cursor snapshot from a previous run, rehydrated into the engine at launch
    /// (see ``bootstrapPersistedState()``). `nil` on a first run.
    private let persistedStateAtLaunch: OutboxPersistenceStore.State?

    init(container: ModelContainer, auth: AuthService) {
        self.container = container
        self.auth = auth

        let clock = SystemClock()
        let idGenerator = UUIDGenerator()
        self.clock = clock
        self.idGenerator = idGenerator
        self.focus = FocusController(clock: clock)

        // The engine writes pulled changes into SwiftData through this store, and persists its outbox
        // + pull cursor through the file-backed store so unsynced work survives an app relaunch (§8).
        let store = SwiftDataSyncStore(container: container)
        let outboxPersistence = OutboxPersistenceStore()
        let saved = outboxPersistence.load()
        self.persistedStateAtLaunch = saved
        self.syncEngine = DefaultSyncEngine(clock: clock, store: store,
                                            initialCursor: saved?.cursor, persister: outboxPersistence)

        // APIClient uses AuthService as its token provider; AuthService is told about the client so
        // it can refresh. (configure(apiClient:) closes the loop.)
        self.apiClient = APIClient(tokenProvider: auth)
        auth.configure(apiClient: self.apiClient)
        self.entitlements = Entitlements(apiClient: self.apiClient)
    }

    /// Rehydrate the durable outbox + pull cursor saved by a previous run (AppSpec §8) so offline edits
    /// survive a relaunch/crash. Call once at launch BEFORE the first sync; the engine guards against a
    /// double restore and against clobbering work enqueued during startup.
    func bootstrapPersistedState() async {
        guard let saved = persistedStateAtLaunch, !(saved.outbox.isEmpty && saved.cursor == nil) else { return }
        await syncEngine.restore(outbox: saved.outbox, cursor: saved.cursor)
    }

    /// Run one sync cycle: flush local mutations, then pull deltas (AppSpec §8).
    ///
    /// Best-effort and safe to call repeatedly. Errors are swallowed in Phase 0; Phase 1 adds
    /// retry/backoff (see `DefaultSyncEngine` TODOs) and surfaces failures.
    func syncOnce() async {
        // TODO(Phase 1): schedule this from BGTaskScheduler + on foreground + after each local
        //   mutation (debounced), and add backoff/jitter. Phase 0 exposes a manual trigger only.
        do {
            _ = try await syncEngine.flush(using: apiClient)
            _ = try await syncEngine.applyPull(using: apiClient)
        } catch {
            #if DEBUG
            print("Sync cycle failed (expected until the backend is reachable): \(error)")
            #endif
        }
    }

    /// The realtime socket (P5-5): on a `sync.bump` it pulls. Lazily created, suppressed in demos.
    private var realtime: RealtimeClient?

    func connectRealtime() async {
        guard !AppConfig.isRunningDemo else { return }
        if realtime == nil {
            realtime = RealtimeClient(apiClient: apiClient, onBump: { [weak self] in await self?.syncOnce() })
        }
        await realtime?.connect()
    }

    func disconnectRealtime() {
        realtime?.disconnect()
    }

    /// Materialize a parsed quick-add (P1-H) into a task: resolve/create its tags by name, create the
    /// task, then apply the parsed priority/due/tags via the standard mutation paths. Returns the id.
    @discardableResult
    func composeQuickAdd(_ parsed: ParsedQuickAdd, ownerId: String) async -> String {
        let ctx = container.mainContext

        // Resolve each tag name to an existing tag or create it.
        var tagIds: [String] = []
        let existing = (try? ctx.fetch(FetchDescriptor<TagModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let tagMut = TagMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator, ownerId: ownerId)
        for name in parsed.tagNames {
            if let match = existing.first(where: { $0.name.lowercased() == name.lowercased() }) {
                tagIds.append(match.id)
            } else if let id = await tagMut.create(name: name) {
                tagIds.append(id)
            }
        }

        let creator = TaskCreation(context: ctx, engine: syncEngine, ownerId: ownerId, clock: clock, idGenerator: idGenerator)
        let id = await creator.createTask(title: parsed.title.isEmpty ? "Untitled" : parsed.title)

        var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let task = try? ctx.fetch(descriptor).first {
            let mut = TaskMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator)
            if parsed.priority != .none { await mut.setPriority(task, parsed.priority) }
            if let due = parsed.dueAt { await mut.reschedule(task, dueAt: due) }
            if !tagIds.isEmpty { await mut.setTags(task, tagIds: tagIds) }
        }
        return id
    }

    /// Publish the agenda widget's data — today's + overdue tasks — to the shared App-Group store so
    /// the WidgetKit extension renders without touching SwiftData (P1-J snapshot pattern). Best-effort;
    /// call after sync. (Cross-process delivery needs the App Groups entitlement; in the unentitled
    /// simulator this writes to the per-process standard defaults.)
    func publishAgenda() async {
        let ctx = container.mainContext
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let now = clock.now()
        let calendar = Calendar.current
        func minute(_ date: Date?) -> Int? {
            guard let date, calendar.isDate(date, inSameDayAs: now) else { return nil }
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let items: [AgendaItem] = tasks.compactMap { task in
            let bucket = SmartListClassifier.classify(status: task.status, dueAt: task.dueAt,
                                                      scheduledStart: task.scheduledStart, now: now)
            guard bucket == .today || bucket == .overdue else { return nil }
            let dueText = task.dueAt.map { $0.formatted(date: .omitted, time: .shortened) }
            return AgendaItem(taskId: task.id, title: task.title, dueText: dueText,
                              isDone: task.status == .done, priorityLevel: task.priority.rawValue,
                              startMinute: minute(task.scheduledStart), endMinute: minute(task.scheduledEnd))
        }
        let snapshot = AgendaSnapshot(items: items, generatedAtEpoch: now.timeIntervalSince1970)
        let defaults = UserDefaults(suiteName: AppConfig.appGroupIdentifier) ?? .standard
        AgendaSnapshotStore.save(snapshot, to: defaults)
    }

    /// Build the notification plan from local reminder records (resolving task titles for the body)
    /// and re-arm the rolling 64-cap window (P1-I). Best-effort; safe to call after each sync. Returns
    /// `(planned, scheduled)` counts for diagnostics.
    @discardableResult
    func scheduleReminders() async -> (planned: Int, scheduled: Int) {
        let ctx = container.mainContext
        let reminders = (try? ctx.fetch(FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskModel>())) ?? []
        let titleById = Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let planned: [PlannedNotification] = reminders.compactMap { reminder in
            guard let fireAt = reminder.fireAt else { return nil }
            return PlannedNotification(reminderId: reminder.id, taskId: reminder.taskId,
                                       fireAt: fireAt, title: titleById[reminder.taskId] ?? "Reminder")
        }
        let plan = NotificationPlanner.plan(reminders: planned, now: clock.now())
        let scheduled = await NotificationScheduler().rearm(plan)
        return (plan.count, scheduled)
    }

    /// The signed-in user's id (owner of generated rows), or a local placeholder pre-sign-in.
    private var ownerId: String {
        if case let .signedIn(userId) = auth.state, let userId { return userId }
        return "local-user"
    }

    /// The current owner id, for UI-driven mutations that stamp a local row (the server re-derives the
    /// authoritative owner from the auth token on push).
    var currentOwnerId: String { ownerId }

    /// Materialize today's routines into scheduled Task instances (P3-3). Idempotent; safe on launch.
    @discardableResult
    func materializeRoutines() async -> Int {
        let service = RoutineMaterializationService(context: container.mainContext, engine: syncEngine,
                                                    clock: clock, idGenerator: idGenerator, ownerId: ownerId)
        return await service.materializeToday()
    }

    /// Re-arm alarm delivery from local alarm records (P3-6). Reuses the same rolling 64-cap planner as
    /// reminders; alarms fire as Time-Sensitive notifications (delivery is device-bound — see
    /// ``AlarmScheduler``). Returns `(planned, scheduled)`.
    @discardableResult
    func scheduleAlarms() async -> (planned: Int, scheduled: Int) {
        let ctx = container.mainContext
        let alarms = (try? ctx.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskModel>())) ?? []
        let titleById = Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let planned: [PlannedNotification] = alarms.compactMap { alarm in
            guard let fireAt = alarm.fireAt else { return nil }
            let title = alarm.taskId.flatMap { titleById[$0] } ?? "Alarm"
            return PlannedNotification(reminderId: alarm.id, taskId: alarm.taskId ?? alarm.id,
                                       fireAt: fireAt, title: title)
        }
        let plan = NotificationPlanner.plan(reminders: planned, now: clock.now())
        let scheduled = await AlarmScheduler().rearm(plan)
        return (plan.count, scheduled)
    }

    /// Re-arm geofence monitoring from local location reminders (kind 2, P3-7). The ≤20-region pick is
    /// pure/tested (GeofencePlanner); the monitoring is device-bound (see ``LocationReminderService``).
    /// Returns the number of regions now monitored.
    @discardableResult
    func rearmLocationReminders(userLocation: GeoPoint? = nil) -> Int {
        let ctx = container.mainContext
        let reminders = (try? ctx.fetch(FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.deletedAt == nil && $0.kind == 2 }))) ?? []
        let located: [LocationReminder] = reminders.compactMap { reminder in
            guard let region = reminder.region else { return nil }
            return LocationReminder(id: reminder.id, region: region)
        }
        let service = LocationReminderService()
        // Ask for Always location in context — only when there's actually a geofence to monitor (and
        // not during a headless demo). Non-blocking; monitoring still no-ops until the user grants it.
        if !located.isEmpty && !AppConfig.isRunningDemo {
            service.requestAuthorization()
        }
        return service.rearm(located, userLocation: userLocation)
    }

    /// Mirror today's scheduled blocks into Apple Calendar (P3-7). The create/update/delete diff is
    /// pure/tested (CalendarSyncPlanner); the EventKit writes are device-bound (see
    /// ``CalendarWriteBackService``). Returns the applied counts.
    @discardableResult
    func exportToCalendar() async -> (created: Int, updated: Int, deleted: Int) {
        let ctx = container.mainContext
        let scheduled = (try? ctx.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let blocks: [CalendarExportBlock] = scheduled.compactMap { task in
            guard let start = task.scheduledStart, let end = task.scheduledEnd else { return nil }
            return CalendarExportBlock(taskId: task.id, title: task.title,
                                       startEpoch: start.timeIntervalSince1970, endEpoch: end.timeIntervalSince1970)
        }
        let service = CalendarWriteBackService()
        // Ask for calendar write access in context — only when there's something to export (and not
        // during a headless demo). writeBack no-ops without authorization, so this stays safe.
        if !blocks.isEmpty && !AppConfig.isRunningDemo {
            _ = await service.requestAccess()
        }
        return await service.writeBack(blocks: blocks, ownerId: ownerId)
    }

    /// Ask for notification authorization (reminders + alarm chains share the notification center,
    /// P1-I/P3-6). Idempotent — iOS returns the existing status without re-prompting. User-initiated
    /// (e.g. a Settings button), so it always asks.
    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        await NotificationScheduler().requestAuthorization()
    }

    /// Launch-time variant: ask once after sign-in, but suppressed during headless demos so the system
    /// prompt can't block them.
    func requestNotificationAuthorizationIfNeeded() async {
        guard !AppConfig.isRunningDemo else { return }
        await requestNotificationAuthorization()
    }

    // MARK: - AI assistant (Phase 4, ApiSpec §9). Every method degrades gracefully: any failure (no
    // consent, no key/503, budget/429, offline) returns nil/empty and the UI uses the on-device path.

    /// Local mirror of the AI opt-in so the UI reflects it without a round-trip (set by the toggle).
    var aiConsentEnabled: Bool { UserDefaults.standard.bool(forKey: "aiConsentEnabled") }

    /// Toggle AI consent: persist locally + tell the server (the gate reads `users.ai_consent`).
    func setAiConsent(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: "aiConsentEnabled")
        _ = try? await apiClient.setAiConsent(enabled)
    }

    /// Cloud NL parse with on-device fallback. Returns the unified ``SyncCore/ParsedQuickAdd`` the
    /// quick-add preview renders — so the UI is identical whether AI or the local parser produced it.
    func aiParseOrLocal(_ text: String) async -> ParsedQuickAdd {
        if aiConsentEnabled {
            let ctx = container.mainContext
            let lists = (try? ctx.fetch(FetchDescriptor<TaskListModel>(predicate: #Predicate { $0.deletedAt == nil })))?.map(\.name) ?? []
            let tags = (try? ctx.fetch(FetchDescriptor<TagModel>(predicate: #Predicate { $0.deletedAt == nil })))?.map(\.name) ?? []
            let request = AIParseRequest(text: text, nowIso: TaskMutation.iso(clock.now()),
                                         lists: lists.isEmpty ? nil : lists, tags: tags.isEmpty ? nil : tags)
            if let parsed = try? await apiClient.aiParse(request) {
                return ParsedQuickAdd(title: parsed.title, dueAt: parsed.due,
                                      tagNames: parsed.tags, priority: parsed.priority.asPriority)
            }
        }
        return QuickAddParser.parse(text) // offline / AI-off / failure fallback
    }

    /// NL search → a structured filter (cloud only; nil ⇒ caller uses its plain text filter).
    func aiSearch(_ query: String) async -> AISearchFilter? {
        guard aiConsentEnabled else { return nil }
        return try? await apiClient.aiSearch(AISearchRequest(query: query, nowIso: TaskMutation.iso(clock.now())))
    }

    /// Auto-plan: gather unscheduled open tasks + today's free slots, ask the server to rank (by the
    /// optional intent) + place. Returns nil if there's nothing to plan or AI is off.
    func aiAutoPlan(intent: String?) async -> AIScheduleProposal? {
        guard aiConsentEnabled else { return nil }
        let ctx = container.mainContext
        let now = clock.now()
        let open = (try? ctx.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.deletedAt == nil })))?
            .filter { $0.scheduledStart == nil && $0.status != .done } ?? []
        guard !open.isEmpty else { return nil }
        let tasks = open.prefix(50).map { task in
            AIScheduleTask(id: task.id, title: task.title, durationMinutes: 30,
                           priority: AIPriority(task.priority), dueIso: task.dueAt.map { TaskMutation.iso($0) })
        }
        let request = AIScheduleRequest(tasks: Array(tasks), freeSlots: todayFreeSlots(now: now),
                                        bufferMinutes: 10, intent: intent)
        return try? await apiClient.aiSchedule(request)
    }

    /// Apply an accepted plan: set each proposed block's task schedule (writes via the normal sync).
    func applyPlan(_ blocks: [AIProposedBlock]) async {
        let ctx = container.mainContext
        let mutation = TaskMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator)
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for block in blocks {
            guard let start = parser.date(from: block.startIso), let end = parser.date(from: block.endIso) else { continue }
            let taskId = block.taskId
            var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == taskId })
            descriptor.fetchLimit = 1
            if let task = try? ctx.fetch(descriptor).first {
                await mutation.setSchedule(task, start: start, end: end)
            }
        }
        if AppConfig.isLiveSync { await syncOnce() }
    }

    /// Stream today's morning brief (empty stream if AI is off).
    func briefStream() async -> AsyncThrowingStream<AINarrativeEvent, Error> {
        guard aiConsentEnabled else { return AsyncThrowingStream { $0.finish() } }
        let ctx = container.mainContext
        let now = clock.now()
        let today = (try? ctx.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.deletedAt == nil })))?
            .filter { task in (task.dueAt.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false)
                || (task.scheduledStart.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false) } ?? []
        let tasks = today.prefix(50).map { task in
            AIBriefTask(title: task.title, priority: AIPriority(task.priority),
                        dueIso: task.dueAt.map { TaskMutation.iso($0) },
                        scheduledStartIso: task.scheduledStart.map { TaskMutation.iso($0) })
        }
        return await apiClient.aiBriefStream(AIBriefRequest(nowIso: TaskMutation.iso(now), tasks: Array(tasks)))
    }

    /// Stream a weekly review from the last 7 days' stats (empty stream if AI is off).
    func reviewStream() async -> AsyncThrowingStream<AINarrativeEvent, Error> {
        guard aiConsentEnabled else { return AsyncThrowingStream { $0.finish() } }
        let ctx = container.mainContext
        let now = clock.now()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let tasks = (try? ctx.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        let created = tasks.filter { $0.createdAt >= weekAgo }.count
        let completed = tasks.filter { $0.status == .done && $0.updatedAt >= weekAgo }.count
        let focus = tasks.reduce(0) { $0 + ($1.actualMinutes ?? 0) }
        let habits = (try? ctx.fetch(FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.deletedAt == nil && $0.isHabit })))?
            .prefix(20).map { AIReviewHabit(name: $0.name, streakCurrent: $0.streakCurrent) } ?? []
        let request = AIReviewRequest(weekStartIso: TaskMutation.iso(weekAgo), completedCount: completed,
                                      createdCount: created, focusMinutes: focus, habits: Array(habits))
        return await apiClient.aiReviewStream(request)
    }

    /// Today's free slots = the working-hours window (09:00–18:00 local) minus any already-scheduled
    /// blocks, starting no earlier than now. A pragmatic default until working hours are user-set.
    private func todayFreeSlots(now: Date) -> [AITimeSlot] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        guard let workStart = cal.date(byAdding: .hour, value: 9, to: startOfDay),
              let workEnd = cal.date(byAdding: .hour, value: 18, to: startOfDay) else { return [] }
        let windowStart = max(now, workStart)
        guard windowStart < workEnd else { return [] }

        // Subtract existing scheduled blocks that overlap the window.
        let ctx = container.mainContext
        let scheduled = ((try? ctx.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.deletedAt == nil })))?
            .compactMap { task -> (Date, Date)? in
                guard let s = task.scheduledStart, let e = task.scheduledEnd, e > windowStart, s < workEnd else { return nil }
                return (max(s, windowStart), min(e, workEnd))
            } ?? []).sorted { $0.0 < $1.0 }

        var slots: [AITimeSlot] = []
        var cursor = windowStart
        for (s, e) in scheduled {
            if s > cursor { slots.append(AITimeSlot(startIso: TaskMutation.iso(cursor), endIso: TaskMutation.iso(s))) }
            cursor = max(cursor, e)
        }
        if cursor < workEnd { slots.append(AITimeSlot(startIso: TaskMutation.iso(cursor), endIso: TaskMutation.iso(workEnd))) }
        return slots
    }

    #if DEBUG
    /// DEBUG (`-livePushDemo`): exercise the REAL create→enqueue→flush path once, proving the
    /// app→server direction against the live API without UI automation. Mirrors `TodayView.addTask`.
    func livePushDemo(ownerId: String) async {
        let creator = TaskCreation(
            context: container.mainContext,
            engine: syncEngine,
            ownerId: ownerId,
            clock: clock,
            idGenerator: idGenerator
        )
        await creator.createTask(title: "From iOS app → Render ✅")
        await syncOnce() // flush the new task to the live API, then pull
    }

    /// DEBUG (`-liveCrudDemo`): create a task then exercise the REAL ``TaskMutation`` path (set
    /// priority, then complete) against the live API — verifies the update→flush direction without UI
    /// automation. Syncs between edits so each carries a fresh `baseVersion`.
    func liveCrudDemo(ownerId: String) async {
        let creator = TaskCreation(context: container.mainContext, engine: syncEngine,
                                   ownerId: ownerId, clock: clock, idGenerator: idGenerator)
        let id = await creator.createTask(title: "Task edited via app ✏️")
        print("CRUD demo: created id=\(id)")
        await syncOnce() // flush create; the pull echo stamps serverVersion locally

        let ctx = container.mainContext
        var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let task = try? ctx.fetch(descriptor).first else { print("CRUD demo: re-fetch FAILED"); return }
        print("CRUD demo: fetched v=\(task.serverVersion) status=\(task.statusRaw)")

        let mutation = TaskMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator)
        await mutation.setPriority(task, .p1)
        await syncOnce()
        await mutation.toggleComplete(task)
        await syncOnce()
        print("CRUD demo: done v=\(task.serverVersion) status=\(task.statusRaw) prio=\(task.priorityRaw)")
    }

    /// DEBUG (`-liveListDemo`): create a list + tag + a task assigned to both via the real mutation
    /// paths, proving list/tag entities round-trip app→server (DevelopmentPlan P1-F).
    func liveListDemo(ownerId: String) async {
        let ctx = container.mainContext
        let listMut = ListMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator, ownerId: ownerId)
        let tagMut = TagMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator, ownerId: ownerId)
        let listId = await listMut.create(name: "Inbox 📥", colorHex: "#F59E0B", icon: "tray")
        let tagId = await tagMut.create(name: "urgent", colorHex: "#EF4444")
        await syncOnce()

        let creator = TaskCreation(context: ctx, engine: syncEngine, ownerId: ownerId, clock: clock, idGenerator: idGenerator)
        let id = await creator.createTask(title: "Triage the inbox", listId: listId)
        await syncOnce()

        if let tagId {
            var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let task = try? ctx.fetch(descriptor).first {
                let taskMut = TaskMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator)
                await taskMut.setTags(task, tagIds: [tagId])
                await syncOnce()
            }
        }
        print("LIST demo: done list=\(listId ?? "nil") tag=\(tagId ?? "nil")")
    }

    /// DEBUG (`-seedDemo`): wipe existing data and seed a realistic, cohesive day — three colored lists,
    /// scheduled blocks across the day (incl. one spanning *now* and one done), due-only markers, and a
    /// couple of inbox tasks — all via the real mutation paths, then flush. Idempotent: re-running first
    /// clears, so it always resets to the same clean set.
    func seedDemoData(ownerId: String) async {
        let ctx = container.mainContext
        let cal = Calendar.current
        let now = clock.now()
        func at(_ h: Int, _ m: Int = 0) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now }

        let listMut = ListMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator, ownerId: ownerId)
        let tagMut = TagMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator, ownerId: ownerId)
        let creator = TaskCreation(context: ctx, engine: syncEngine, ownerId: ownerId, clock: clock, idGenerator: idGenerator)
        let taskMut = TaskMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator)

        // Clean slate so a reseed is deterministic (clears prior test junk too).
        for t in (try? ctx.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? [] {
            await taskMut.delete(t)
        }
        for l in (try? ctx.fetch(FetchDescriptor<TaskListModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? [] {
            await listMut.delete(l)
        }
        for tag in (try? ctx.fetch(FetchDescriptor<TagModel>(predicate: #Predicate { $0.deletedAt == nil }))) ?? [] {
            await tagMut.delete(tag)
        }
        await syncOnce()

        let work = await listMut.create(name: "Work", colorHex: "#2E7DF6", icon: "briefcase.fill")
        let health = await listMut.create(name: "Health", colorHex: "#34C759", icon: "heart.fill")
        let personal = await listMut.create(name: "Personal", colorHex: "#FF9F0A", icon: "house.fill")
        _ = await tagMut.create(name: "urgent", colorHex: "#EF4444")
        _ = await tagMut.create(name: "focus", colorHex: "#5E5CE6")
        await syncOnce()

        func fetch(_ id: String) -> TaskModel? {
            var d = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
            return try? ctx.fetch(d).first
        }
        func scheduled(_ title: String, _ list: String?, _ sh: Int, _ sm: Int, _ eh: Int, _ em: Int,
                       priority: Priority = .none, done: Bool = false) async {
            let id = await creator.createTask(title: title, listId: list)
            guard let t = fetch(id) else { return }
            await taskMut.setSchedule(t, start: at(sh, sm), end: at(eh, em))
            if priority != .none { await taskMut.setPriority(t, priority) }
            if done { await taskMut.toggleComplete(t) }
        }

        // A block spanning "now" → the emphasised current arc.
        let nowId = await creator.createTask(title: "Focus block", listId: work)
        if let t = fetch(nowId) {
            await taskMut.setSchedule(t, start: now.addingTimeInterval(-30 * 60), end: now.addingTimeInterval(60 * 60))
            await taskMut.setPriority(t, .p1)
        }
        await scheduled("Morning run", health, 6, 30, 7, 15, priority: .p3, done: true)
        await scheduled("Deep work — API design", work, 9, 0, 11, 0, priority: .p1)
        await scheduled("Lunch with Sam", personal, 12, 0, 13, 0)
        await scheduled("Team sync", work, 13, 30, 14, 15, priority: .p2)
        await scheduled("Gym session", health, 18, 0, 19, 0, priority: .p3)

        // Due-only tasks → instant markers on the dial.
        let dentist = await creator.createTask(title: "Call the dentist", listId: personal)
        if let t = fetch(dentist) { await taskMut.reschedule(t, dueAt: at(16, 0)); await taskMut.setPriority(t, .p2) }
        let expense = await creator.createTask(title: "Submit expense report", listId: work)
        if let t = fetch(expense) { await taskMut.reschedule(t, dueAt: at(17, 30)) }

        // A couple of unscheduled inbox tasks.
        _ = await creator.createTask(title: "Read “Deep Work”, ch. 3", listId: personal)
        _ = await creator.createTask(title: "Plan next sprint", listId: work)

        // Keeper: a couple of folders + notes (one pinned, one unfiled).
        let folderMut = NoteFolderMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator, ownerId: ownerId)
        let noteMut = NoteMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator, ownerId: ownerId)
        let ideas = await folderMut.create(name: "Ideas", colorHex: "#5E5CE6", icon: "lightbulb.fill")
        let workNotes = await folderMut.create(name: "Work", colorHex: "#2E7DF6", icon: "briefcase.fill")
        await syncOnce()
        _ = await noteMut.create(title: "App launch checklist", folderId: workNotes,
                                 body: "TestFlight build · screenshots · privacy labels · subscription products.")
        _ = await noteMut.create(title: "Idea: weekly digest", folderId: ideas,
                                 body: "Email a Sunday recap of streaks + next week's plan.")
        let pinnedId = await noteMut.create(title: "Wifi & door codes", folderId: nil,
                                            body: "Office wifi: DoIT-Guest / keep-it-simple")
        if let pinnedId {
            var d = FetchDescriptor<NoteModel>(predicate: #Predicate { $0.id == pinnedId }); d.fetchLimit = 1
            if let note = try? ctx.fetch(d).first { await noteMut.setPinned(note, true) }
        }

        await syncOnce()
        print("SEED demo: done")
    }

    /// DEBUG (`-liveQuickAddDemo`): parse a natural-language phrase and compose it into a task via the
    /// real `composeQuickAdd` path, proving P1-H end-to-end (parse → fields → server).
    func liveQuickAddDemo(ownerId: String) async {
        let parsed = QuickAddParser.parse("Call the dentist tomorrow 9am #health !p2")
        print("QUICKADD demo: parsed title=\(parsed.title) due=\(parsed.dueAt != nil) tags=\(parsed.tagNames) prio=\(parsed.priority)")
        await composeQuickAdd(parsed, ownerId: ownerId)
        await syncOnce()
    }

    /// DEBUG (`-liveFocusDemo`): log 25 focus-minutes on one task via the real FocusSession→
    /// actualMinutes path (verifies P2-4 logging), then start a live focus session on another so the
    /// running timer can be shown.
    func liveFocusDemo(ownerId: String) async {
        let ctx = container.mainContext
        let creator = TaskCreation(context: ctx, engine: syncEngine, ownerId: ownerId, clock: clock, idGenerator: idGenerator)

        let loggedId = await creator.createTask(title: "Logged 25m focus ✅")
        await syncOnce()
        var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == loggedId })
        descriptor.fetchLimit = 1
        if let task = try? ctx.fetch(descriptor).first {
            let session = FocusSession(taskId: loggedId, taskTitle: task.title, accumulatedSeconds: 25 * 60)
            let minutes = session.loggedMinutes(at: clock.now().timeIntervalSince1970)
            await TaskMutation(context: ctx, engine: syncEngine, clock: clock, idGenerator: idGenerator)
                .addActualMinutes(task, minutes)
            await syncOnce()
            print("FOCUS demo: logged \(minutes)m actualMinutes on \(loggedId)")
        }

        let runId = await creator.createTask(title: "Focusing now…")
        await syncOnce()
        focus.start(taskId: runId, title: "Focusing now…")
    }

    /// DEBUG (`-liveRoutineDemo`): create a daily 3-step routine, flush it, then materialize today's
    /// instances — proves P3-3 (routine → scheduled Task instances tagged routineInstanceOf).
    func liveRoutineDemo(ownerId: String) async {
        let ctx = container.mainContext
        let now = clock.now()
        let id = idGenerator.newID()
        let routine = RoutineModel(
            id: id, ownerId: ownerId, name: "Morning routine", colorHex: "#10B981",
            anchorTime: "06:30", chained: true, isHabit: false,
            createdAt: now, updatedAt: now, serverVersion: 0, syncStateRaw: LocalSyncState.pendingCreate.rawValue
        )
        routine.steps = [
            RoutineStep(title: "Meditate", minutes: 10, ord: 0),
            RoutineStep(title: "Gym", minutes: 60, ord: 1),
            RoutineStep(title: "Read", minutes: 30, ord: 2),
        ]
        ctx.insert(routine)
        try? ctx.save()

        let stepsField: AnyCodable = .array(routine.steps.map { step in
            .object(["title": .string(step.title), "minutes": .int(step.minutes),
                     "ord": .int(step.ord), "hasAlarm": .bool(step.hasAlarm)])
        })
        await syncEngine.enqueue(OutboxOp(
            opId: idGenerator.newID(), entityType: .routine, entityId: id, op: .upsert,
            baseVersion: 0, clientUpdatedAt: now,
            fields: ["name": .string("Morning routine"), "colorHex": .string("#10B981"),
                     "anchorTime": .string("06:30"), "chained": .bool(true), "isHabit": .bool(false),
                     "graceDays": .int(0), "steps": stepsField],
            enqueuedAt: now
        ))
        await syncOnce()
        let count = await materializeRoutines()
        await syncOnce()
        print("ROUTINE demo: created routine + materialized \(count) step instances")
    }

    /// DEBUG (`-liveAlarmDemo`): create a routine whose first step `hasAlarm`, materialize it (which
    /// forges the alarm "chain" — one Alarm per alarmed step), add one explicit future alarm, then
    /// re-arm the scheduler. Proves P3-6: alarm entities sync app→server + the 64-cap scheduler runs.
    func liveAlarmDemo(ownerId: String) async {
        let ctx = container.mainContext
        let now = clock.now()

        // A routine with an alarmed first step → materialization creates the alarm chain.
        let routineId = idGenerator.newID()
        let routine = RoutineModel(
            id: routineId, ownerId: ownerId, name: "Wake & train", colorHex: "#EF4444",
            anchorTime: "07:00", chained: true, isHabit: false,
            createdAt: now, updatedAt: now, serverVersion: 0, syncStateRaw: LocalSyncState.pendingCreate.rawValue
        )
        routine.steps = [
            RoutineStep(title: "Wake up", minutes: 5, ord: 0, hasAlarm: true),
            RoutineStep(title: "Train", minutes: 60, ord: 1, hasAlarm: false),
        ]
        ctx.insert(routine)
        try? ctx.save()
        let stepsField: AnyCodable = .array(routine.steps.map { step in
            .object(["title": .string(step.title), "minutes": .int(step.minutes),
                     "ord": .int(step.ord), "hasAlarm": .bool(step.hasAlarm)])
        })
        await syncEngine.enqueue(OutboxOp(
            opId: idGenerator.newID(), entityType: .routine, entityId: routineId, op: .upsert,
            baseVersion: 0, clientUpdatedAt: now,
            fields: ["name": .string("Wake & train"), "colorHex": .string("#EF4444"),
                     "anchorTime": .string("07:00"), "chained": .bool(true), "isHabit": .bool(false),
                     "graceDays": .int(0), "steps": stepsField],
            enqueuedAt: now
        ))
        await syncOnce()
        let materialized = await materializeRoutines() // creates Task instances + the alarm chain

        // One explicit future alarm so the scheduler always has something to arm (run-time independent).
        let alarmMutation = AlarmMutation(context: ctx, engine: syncEngine, clock: clock,
                                          idGenerator: idGenerator, ownerId: ownerId)
        _ = await alarmMutation.create(fireAt: now.addingTimeInterval(3600), type: 0, usesLiveActivity: true)
        await syncOnce() // push routine alarm chain + the explicit alarm to the server

        let alarmCount = (try? ctx.fetch(FetchDescriptor<AlarmModel>(predicate: #Predicate { $0.deletedAt == nil })))?.count ?? -1
        let result = await scheduleAlarms()
        let pending = await AlarmScheduler().pendingAlarmCount()
        print("ALARM demo: materialized=\(materialized), alarmRecords=\(alarmCount), planned=\(result.planned), scheduled=\(result.scheduled), pending=\(pending)")
    }

    /// DEBUG (`-liveHabitDemo`): create a habit via the real RoutineMutation, flush it, then log today
    /// — proving P3-4's habit log path (client → /habits/log → server streak → synced back).
    func liveHabitDemo(ownerId: String) async {
        let ctx = container.mainContext
        let mutation = RoutineMutation(context: ctx, engine: syncEngine, apiClient: apiClient,
                                       clock: clock, idGenerator: idGenerator, ownerId: ownerId)
        let id = await mutation.create(name: "Read 30 min", isHabit: true, graceDays: 1)
        await syncOnce() // flush the habit so the server has it before /habits/log

        // Log the last 5 days for a visible streak + heatmap.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for offset in [-4, -3, -2, -1, 0] {
            let date = formatter.string(from: clock.now().addingTimeInterval(Double(offset) * 86_400))
            _ = try? await apiClient.logHabit(routineId: id, date: date)
        }
        await syncOnce() // pull the server-updated routine (streak + completions)

        var descriptor = FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let habit = try? ctx.fetch(descriptor).first {
            print("HABIT demo: created \(id), streakCurrent=\(habit.streakCurrent), completions=\(habit.completions.count)")
        }
    }

    /// DEBUG (`-liveReminderDemo`): insert a task + 70 future reminders locally, then schedule them —
    /// proves the reminder `@Model` + the 64-cap re-arm scheduler (pending count caps at 64).
    func liveReminderDemo(ownerId: String) async {
        let ctx = container.mainContext
        let now = clock.now()
        let taskId = idGenerator.newID()
        ctx.insert(TaskModel(id: taskId, ownerId: ownerId, title: "Reminder stress test",
                             statusRaw: TaskStatus.inbox.rawValue, createdAt: now, updatedAt: now,
                             serverVersion: 0, syncStateRaw: LocalSyncState.synced.rawValue))
        for i in 1...70 {
            ctx.insert(ReminderModel(id: idGenerator.newID(), ownerId: ownerId, taskId: taskId, kind: 0,
                                     fireAt: now.addingTimeInterval(Double(i) * 3600), interruption: 1,
                                     createdAt: now, updatedAt: now, serverVersion: 0,
                                     syncStateRaw: LocalSyncState.synced.rawValue))
        }
        do { try ctx.save() } catch { print("REMINDER demo: SAVE ERROR \(error)") }
        let fetched = (try? ctx.fetch(FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.deletedAt == nil })))?.count ?? -1
        let result = await scheduleReminders()
        let pending = await NotificationScheduler().pendingCount()
        print("REMINDER demo: inserted 70, fetched=\(fetched), planned=\(result.planned), scheduled=\(result.scheduled), pending=\(pending) (cap \(NotificationPlanner.systemPendingCap))")
    }

    /// DEBUG (`-liveLocationDemo`): create a task + a geofenced (kind 2) reminder via the real
    /// ReminderMutation, flush it (proving region syncs app→server), then re-arm region monitoring.
    /// The region round-trip is verifiable on the live server; the monitoring is device-bound.
    func liveLocationDemo(ownerId: String) async {
        let ctx = container.mainContext
        // Push the task first (real outbox path) so it exists on the server before the reminder — the
        // server's reminders.task_id FK rejects a reminder for a task it hasn't seen.
        let creator = TaskCreation(context: ctx, engine: syncEngine, ownerId: ownerId,
                                   clock: clock, idGenerator: idGenerator)
        let taskId = await creator.createTask(title: "Buy milk near the store")
        await syncOnce()

        let mutation = ReminderMutation(context: ctx, engine: syncEngine, clock: clock,
                                        idGenerator: idGenerator, ownerId: ownerId)
        let region = ReminderRegion(center: GeoPoint(lat: 1.3521, lon: 103.8198, name: "Store"),
                                    radius: 150, onEntry: true, onExit: false)
        let id = await mutation.createLocation(taskId: taskId, region: region)
        await syncOnce() // push the location reminder (with region) to the live server

        let monitored = rearmLocationReminders(userLocation: GeoPoint(lat: 1.35, lon: 103.82))
        print("LOCATION demo: created reminder \(id.prefix(8)) region=(\(region.center.lat),\(region.center.lon)) r=\(region.radius), monitored=\(monitored) (cap \(GeofencePlanner.systemRegionCap))")
    }

    /// DEBUG (`-liveCalendarDemo`): insert two scheduled tasks, then run calendar write-back. The diff
    /// (CalendarSyncPlanner) is pure/tested; the EventKit writes are device-bound (0s without calendar
    /// permission). Prints both the planned and applied counts.
    func liveCalendarDemo(ownerId: String) async {
        let ctx = container.mainContext
        let now = clock.now()
        for (i, title) in ["Deep work", "Gym session"].enumerated() {
            let task = TaskModel(id: idGenerator.newID(), ownerId: ownerId, title: title,
                                 statusRaw: TaskStatus.scheduled.rawValue, createdAt: now, updatedAt: now,
                                 serverVersion: 0, syncStateRaw: LocalSyncState.synced.rawValue)
            task.scheduledStart = now.addingTimeInterval(Double(i + 1) * 3600)
            task.scheduledEnd = now.addingTimeInterval(Double(i + 1) * 3600 + 1800)
            ctx.insert(task)
        }
        try? ctx.save()

        let scheduled = (try? ctx.fetch(FetchDescriptor<TaskModel>(predicate: #Predicate { $0.deletedAt == nil })))?
            .filter { $0.scheduledStart != nil } ?? []
        let blocks = scheduled.compactMap { task -> CalendarExportBlock? in
            guard let start = task.scheduledStart, let end = task.scheduledEnd else { return nil }
            return CalendarExportBlock(taskId: task.id, title: task.title,
                                       startEpoch: start.timeIntervalSince1970, endEpoch: end.timeIntervalSince1970)
        }
        let plan = CalendarSyncPlanner.plan(blocks: blocks, existing: [])
        let applied = await exportToCalendar()
        print("CALENDAR demo: \(blocks.count) blocks, planned creates=\(plan.creates.count), applied=(c:\(applied.created), u:\(applied.updated), d:\(applied.deleted)) [device-bound: 0s without calendar permission]")
    }
    #endif
}
