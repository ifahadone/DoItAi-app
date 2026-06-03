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
        ChecklistItemModel.self
    ])

    /// The shared, App-Group-backed container used by the app and its extensions.
    @MainActor
    static func makeShared() -> ModelContainer {
        // Prefer the App Group store (shared with widgets/Live Activity, AppSpec §9). SwiftData
        // *fatalErrors* — it does not throw — when the group is absent from the app's entitlements,
        // so a do/catch can't recover. Check the container is actually available first, and only then
        // request the group-backed store; otherwise fall back to the app's default store so the app
        // still launches (e.g. in the simulator before the App Groups capability is configured — see
        // README).
        let groupAvailable = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConfig.appGroupIdentifier) != nil

        if groupAvailable {
            let configuration = ModelConfiguration(
                schema: schema,
                groupContainer: .identifier(AppConfig.appGroupIdentifier),
                cloudKitDatabase: .none // sync is via the DoIT API, not CloudKit (AppSpec §8)
            )
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
                return container
            }
        }

        #if DEBUG
        if !groupAvailable {
            print("⚠️ App Group '\(AppConfig.appGroupIdentifier)' not entitled; using the default store. " +
                  "Enable the App Groups capability to share data with widgets — see README.")
        }
        #endif

        // TODO(Phase 1): surface failures via an onboarding/error path and add a SchemaMigrationPlan
        //   before the store ships with real user data.
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create SwiftData ModelContainer: \(error)")
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
