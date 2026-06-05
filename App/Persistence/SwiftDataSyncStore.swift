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
        // `task`, `list`, and `tag` persist locally. `reminder`/`checklist` are skipped until their
        // @Models land — an unmodeled entityType still decodes upstream and is simply no-op'd here,
        // never crashing (forward-compat, ApiSpec §13).
        switch change.entityType {
        case .task: try await applyTask(change)
        case .list: try await applyList(change)
        case .tag:  try await applyTag(change)
        case .reminder: try await applyReminder(change)
        case .checklist: try await applyChecklist(change)
        case .routine: try await applyRoutine(change)
        case .alarm: try await applyAlarm(change)
        case .noteFolder: try await applyNoteFolder(change)
        case .note: try await applyNote(change)
        default:
            // Forward-compat: an entity type this build doesn't model yet decodes upstream and is
            // simply skipped here, never crashing (ApiSpec §13).
            return
        }
    }

    // MARK: - Per-entity apply (upsert / tombstone)

    @MainActor
    private func applyTask(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let existing = try fetchTask(id: change.entityId, in: context)
        switch change.op {
        case .delete:
            markDeleted(existing, version: change.version)
        case .upsert:
            guard let payload = change.payload else { return }
            let dto = try Self.decode(payload, as: TaskDTO.self)
            if let existing { existing.apply(dto) } else { context.insert(TaskModel.make(from: dto)) }
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    private func applyList(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let existing = try fetchList(id: change.entityId, in: context)
        switch change.op {
        case .delete:
            markDeleted(existing, version: change.version)
        case .upsert:
            guard let payload = change.payload else { return }
            let dto = try Self.decode(payload, as: TaskListDTO.self)
            if let existing { existing.apply(dto) } else { context.insert(TaskListModel.make(from: dto)) }
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    private func applyTag(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let existing = try fetchTag(id: change.entityId, in: context)
        switch change.op {
        case .delete:
            markDeleted(existing, version: change.version)
        case .upsert:
            guard let payload = change.payload else { return }
            let dto = try Self.decode(payload, as: TagDTO.self)
            if let existing { existing.apply(dto) } else { context.insert(TagModel.make(from: dto)) }
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    private func applyReminder(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let existing = try fetchReminder(id: change.entityId, in: context)
        switch change.op {
        case .delete:
            markDeleted(existing, version: change.version)
        case .upsert:
            guard let payload = change.payload else { return }
            let dto = try Self.decode(payload, as: ReminderDTO.self)
            if let existing { existing.apply(dto) } else { context.insert(ReminderModel.make(from: dto)) }
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    private func applyChecklist(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let existing = try fetchChecklist(id: change.entityId, in: context)
        switch change.op {
        case .delete:
            markDeleted(existing, version: change.version)
        case .upsert:
            guard let payload = change.payload else { return }
            let dto = try Self.decode(payload, as: ChecklistItemDTO.self)
            if let existing { existing.apply(dto) } else { context.insert(ChecklistItemModel.make(from: dto)) }
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    private func applyRoutine(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let existing = try fetchRoutine(id: change.entityId, in: context)
        switch change.op {
        case .delete:
            markDeleted(existing, version: change.version)
        case .upsert:
            guard let payload = change.payload else { return }
            let dto = try Self.decode(payload, as: RoutineDTO.self)
            if let existing { existing.apply(dto) } else { context.insert(RoutineModel.make(from: dto)) }
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    private func applyAlarm(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let existing = try fetchAlarm(id: change.entityId, in: context)
        switch change.op {
        case .delete:
            markDeleted(existing, version: change.version)
        case .upsert:
            guard let payload = change.payload else { return }
            let dto = try Self.decode(payload, as: AlarmDTO.self)
            if let existing { existing.apply(dto) } else { context.insert(AlarmModel.make(from: dto)) }
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    private func applyNoteFolder(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let existing = try fetchNoteFolder(id: change.entityId, in: context)
        switch change.op {
        case .delete:
            markDeleted(existing, version: change.version)
        case .upsert:
            guard let payload = change.payload else { return }
            let dto = try Self.decode(payload, as: NoteFolderDTO.self)
            if let existing { existing.apply(dto) } else { context.insert(NoteFolderModel.make(from: dto)) }
        }
        if context.hasChanges { try context.save() }
    }

    @MainActor
    private func applyNote(_ change: SyncPullChange) async throws {
        let context = container.mainContext
        let existing = try fetchNote(id: change.entityId, in: context)
        switch change.op {
        case .delete:
            markDeleted(existing, version: change.version)
        case .upsert:
            guard let payload = change.payload else { return }
            let dto = try Self.decode(payload, as: NoteDTO.self)
            if let existing { existing.apply(dto) } else { context.insert(NoteModel.make(from: dto)) }
        }
        if context.hasChanges { try context.save() }
    }

    // MARK: - Helpers

    /// Apply a tombstone: mark the local row deleted (Phase 0 keeps the row; a Phase 1 GC purges it).
    /// No-op when the row was never seen locally — there's nothing to tombstone.
    @MainActor
    private func markDeleted<M: SyncTombstonable>(_ model: M?, version: Int) {
        guard let model else { return }
        model.deletedAt = model.deletedAt ?? Date(timeIntervalSince1970: 0)
        model.serverVersion = version
        model.syncStateRaw = LocalSyncState.synced.rawValue
    }

    @MainActor
    private func fetchTask(id: String, in context: ModelContext) throws -> TaskModel? {
        var d = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try context.fetch(d).first
    }

    @MainActor
    private func fetchList(id: String, in context: ModelContext) throws -> TaskListModel? {
        var d = FetchDescriptor<TaskListModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try context.fetch(d).first
    }

    @MainActor
    private func fetchTag(id: String, in context: ModelContext) throws -> TagModel? {
        var d = FetchDescriptor<TagModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try context.fetch(d).first
    }

    @MainActor
    private func fetchReminder(id: String, in context: ModelContext) throws -> ReminderModel? {
        var d = FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try context.fetch(d).first
    }

    @MainActor
    private func fetchChecklist(id: String, in context: ModelContext) throws -> ChecklistItemModel? {
        var d = FetchDescriptor<ChecklistItemModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try context.fetch(d).first
    }

    @MainActor
    private func fetchRoutine(id: String, in context: ModelContext) throws -> RoutineModel? {
        var d = FetchDescriptor<RoutineModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try context.fetch(d).first
    }

    @MainActor
    private func fetchAlarm(id: String, in context: ModelContext) throws -> AlarmModel? {
        var d = FetchDescriptor<AlarmModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try context.fetch(d).first
    }

    @MainActor
    private func fetchNoteFolder(id: String, in context: ModelContext) throws -> NoteFolderModel? {
        var d = FetchDescriptor<NoteFolderModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try context.fetch(d).first
    }

    @MainActor
    private func fetchNote(id: String, in context: ModelContext) throws -> NoteModel? {
        var d = FetchDescriptor<NoteModel>(predicate: #Predicate { $0.id == id }); d.fetchLimit = 1
        return try context.fetch(d).first
    }

    /// Re-materialize an erased pull payload into a concrete DTO using the shared coders.
    static func decode<T: Decodable>(_ payload: AnyCodable, as _: T.Type) throws -> T {
        let data = try JSONCoding.makeEncoder().encode(payload)
        return try JSONCoding.makeDecoder().decode(T.self, from: data)
    }
}

/// The minimal surface ``SwiftDataSyncStore/markDeleted`` needs to tombstone any synced row.
protocol SyncTombstonable: AnyObject {
    var deletedAt: Date? { get set }
    var serverVersion: Int { get set }
    var syncStateRaw: Int { get set }
}

extension TaskModel: SyncTombstonable {}
extension TaskListModel: SyncTombstonable {}
extension TagModel: SyncTombstonable {}
extension ReminderModel: SyncTombstonable {}
extension ChecklistItemModel: SyncTombstonable {}
extension RoutineModel: SyncTombstonable {}
extension AlarmModel: SyncTombstonable {}
extension NoteFolderModel: SyncTombstonable {}
extension NoteModel: SyncTombstonable {}
