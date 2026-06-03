import Foundation
import SwiftData
import SyncCore

/// Bridges ``SyncCore/SyncStore`` to the SwiftData container: applies pulled deltas (upserts and
/// tombstones) into local `@Model` rows (AppSpec §8). This is the app-target half of the sync loop —
/// SyncCore decides *what* changed; this decides *how to persist it*.
///
/// Runs all writes on the `@MainActor` via a `ModelContext` because SwiftData's default context is
/// main-actor bound. The actor-isolated ``DefaultSyncEngine`` calls `apply(_:)` and awaits the hop.
///
/// Requires the Xcode app target (SwiftData). Not built by the SPM packages.
struct SwiftDataSyncStore: SyncStore {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func apply(_ change: SyncPullChange) async throws {
        // Only `task` is modeled in Phase 0; other entity types are skipped (forward-compat,
        // ApiSpec §13). Later phases add list/tag/routine/… cases here.
        switch change.entityType {
        case .task:
            try await applyTask(change)
        default:
            // TODO(Phase 1): handle list, tag, routine, reminder, alarm, event upserts/tombstones.
            return
        }
    }

    @MainActor
    private func applyTask(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let entityId = change.entityId
        let existing = try fetchTask(id: entityId, in: context)

        switch change.op {
        case .delete:
            // Tombstone: mark deleted locally (or hard-delete — Phase 0 marks + keeps the row).
            if let existing {
                existing.deletedAt = existing.deletedAt ?? Date(timeIntervalSince1970: 0)
                existing.serverVersion = change.version
                existing.syncState = .synced
            }
            // TODO(Phase 1): decide retention — purge tombstoned rows after a window (mirrors the
            //   server's gc.tombstones, ApiSpec §11).

        case .upsert:
            guard let payload = change.payload else { return }
            // Decode the type-erased payload into TaskDTO by re-encoding then decoding.
            let dto = try Self.decodeTaskPayload(payload)
            if let existing {
                existing.apply(dto)
            } else {
                context.insert(TaskModel.make(from: dto))
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }

    @MainActor
    private func fetchTask(id: String, in context: ModelContext) throws -> TaskModel? {
        var descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Re-materialize the erased pull payload into a concrete ``TaskDTO`` using the shared coders.
    static func decodeTaskPayload(_ payload: AnyCodable) throws -> TaskDTO {
        let data = try JSONCoding.makeEncoder().encode(payload)
        return try JSONCoding.makeDecoder().decode(TaskDTO.self, from: data)
    }
}
