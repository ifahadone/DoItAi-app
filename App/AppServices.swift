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

    private let container: ModelContainer

    init(container: ModelContainer, auth: AuthService) {
        self.container = container
        self.auth = auth

        let clock = SystemClock()
        let idGenerator = UUIDGenerator()
        self.clock = clock
        self.idGenerator = idGenerator

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
    #endif
}
