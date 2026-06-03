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
        TagModel.self
    ])

    /// The shared, App-Group-backed container used by the app and its extensions.
    @MainActor
    static func makeShared() -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            // Persist into the App Group so widgets/Live Activity share the store.
            groupContainer: .identifier(AppConfig.appGroupIdentifier),
            cloudKitDatabase: .none // sync is via the DoIT API, not CloudKit (AppSpec §8)
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // TODO(Phase 1): surface this via an onboarding/error path and add a migration plan
            //   (SchemaMigrationPlan) before the store ships with real user data. For Phase 0 we
            //   fall back to a default (non-App-Group) store so the app still launches in the
            //   simulator before the capability is configured.
            #if DEBUG
            print("⚠️ App Group container unavailable (\(AppConfig.appGroupIdentifier)): \(error). " +
                  "Falling back to default store. Enable the App Groups capability — see README.")
            #endif
            do {
                return try ModelContainer(for: schema)
            } catch {
                fatalError("Unable to create SwiftData ModelContainer: \(error)")
            }
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
