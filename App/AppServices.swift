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

    private let container: ModelContainer

    init(container: ModelContainer, auth: AuthService) {
        self.container = container
        self.auth = auth

        let clock = SystemClock()
        let idGenerator = UUIDGenerator()
        self.clock = clock
        self.idGenerator = idGenerator
        self.focus = FocusController(clock: clock)

        // The engine writes pulled changes into SwiftData through this store.
        let store = SwiftDataSyncStore(container: container)
        self.syncEngine = DefaultSyncEngine(clock: clock, store: store)

        // APIClient uses AuthService as its token provider; AuthService is told about the client so
        // it can refresh. (configure(apiClient:) closes the loop.)
        self.apiClient = APIClient(tokenProvider: auth)
        auth.configure(apiClient: self.apiClient)
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
    #endif
}
