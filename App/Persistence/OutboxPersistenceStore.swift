import Foundation
import SyncCore

/// File-backed durable backing for the sync outbox + pull cursor (AppSpec §8). The outbox is the
/// source of unsynced work, so it must survive an app relaunch or crash; the cursor must persist so
/// sync resumes incrementally instead of re-pulling the whole change log from zero.
///
/// Conforms to ``SyncCore/SyncStatePersisting`` — the engine calls `save` on its actor whenever the
/// queue or cursor changes. Writes are encoded on the caller and the file I/O is offloaded to a
/// serial background queue with an atomic replace, so persisting never blocks the engine actor and a
/// crash mid-write can't corrupt the file. The payload is small (pending ops only), so JSON is fine.
final class OutboxPersistenceStore: SyncStatePersisting, @unchecked Sendable {
    /// The persisted snapshot: the pending queue + the last pull cursor.
    struct State: Codable {
        var outbox: [OutboxOp]
        var cursor: String?
    }

    private let url: URL
    private let io = DispatchQueue(label: "app.doit.outbox-persistence")

    init(filename: String = "sync-outbox.json") {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        self.url = base.appendingPathComponent(filename)
    }

    /// Synchronously decode the persisted state (called once at launch, before the first sync). Returns
    /// `nil` on a first run or any decode failure — sync then starts clean rather than crashing.
    func load() -> State? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    // MARK: - SyncStatePersisting

    func save(outbox: [OutboxOp], cursor: String?) {
        let state = State(outbox: outbox, cursor: cursor)
        guard let data = try? JSONEncoder().encode(state) else { return }
        io.async { [url] in try? data.write(to: url, options: .atomic) }
    }
}
