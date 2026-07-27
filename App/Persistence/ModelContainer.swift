import Foundation
import SwiftData

/// Builds the shared SwiftData `ModelContainer` (AppSpec §7, §9).
///
/// The store lives in the **App Group** container (``AppConfig/appGroupIdentifier``) so the app,
/// widgets, and Live Activity all read the same data. This requires the *App Groups* capability with
/// a matching group id enabled on every target (see README) — without it, `groupContainer` resolution
/// fails at runtime, so we fall back to the app's default store and log loudly in DEBUG.
///
/// Requires the Xcode app target (SwiftData). Not built by `swift build` on the SPM packages.
enum PersistenceContainer {
    /// All `@Model` types the container must know about. Add new models here as phases land.
    static let schema = Schema([
        TaskModel.self,
        TaskListModel.self,
        TagModel.self,
        ReminderModel.self,
        ChecklistItemModel.self,
        RoutineModel.self,
        AlarmModel.self,
        NoteFolderModel.self,
        NoteModel.self
    ])

    /// The shared, App-Group-backed container used by the app and its extensions.
    @MainActor
    static func makeShared() -> ModelContainer {
        // Prefer the App Group store (shared with widgets/Live Activity, AppSpec §9). SwiftData
        // *fatalErrors* — it does not throw — when the group is absent from the app's entitlements,
        // so we check availability first and only then request the group-backed store; otherwise use
        // the app's default store so the app still launches (e.g. in the simulator before the App
        // Groups capability is configured — see README).
        let groupAvailable = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier) != nil

        #if DEBUG
        if !groupAvailable {
            print("⚠️ App Group '\(AppConfig.appGroupIdentifier)' not entitled; using the default store. " +
                  "Enable the App Groups capability to share data with widgets — see README.")
        }
        #endif

        let configuration: ModelConfiguration = groupAvailable
            ? ModelConfiguration(schema: schema,
                                 groupContainer: .identifier(AppConfig.appGroupIdentifier),
                                 cloudKitDatabase: .none) // sync is via the DoIT API, not CloudKit (§8)
            : ModelConfiguration(schema: schema)

        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }

        // Recovery: the on-disk store is incompatible (a model changed without a SchemaMigrationPlan) or
        // corrupt. Rather than crash on launch, wipe the store and retry once — the DoIT server is the
        // source of truth for signed-in users (they re-sync), and a device-only user gets a clean slate,
        // which still beats an unrecoverable crash. TODO(Phase 1): add a SchemaMigrationPlan + surface
        // this via an onboarding/error path before shipping breaking model changes with real user data.
        #if DEBUG
        print("⚠️ SwiftData store unopenable — wiping and retrying (incompatible schema or corruption).")
        #endif
        wipeStore(at: configuration.url)
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return container
        }

        // Last resort: launch on an in-memory store (non-persistent) instead of crashing.
        #if DEBUG
        print("⚠️ Falling back to an in-memory store; changes won't persist until the next launch.")
        #endif
        return makeInMemory()
    }

    /// Delete a SwiftData store file and its `-wal`/`-shm` siblings (best-effort). Used to recover from
    /// an unopenable/incompatible on-disk store before retrying.
    private static func wipeStore(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: url.path + suffix)
        }
    }

    /// An in-memory container for previews and unit/UI tests (no disk, no App Group).
    @MainActor
    static func makeInMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create in-memory ModelContainer: \(error)")
        }
    }
}
