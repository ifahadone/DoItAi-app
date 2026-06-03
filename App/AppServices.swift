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
    #endif
}
