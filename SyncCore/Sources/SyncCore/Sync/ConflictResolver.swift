import Foundation

/// Outcome of resolving a local change against a concurrent server change.
///
/// Mirrors the per-op statuses the server returns (ApiSpec §6.1), computed on the client so the
/// outbox can pre-empt obvious losses and so the same rules can be unit-tested without a server.
public enum ConflictOutcome: Equatable, Sendable {
    /// Base version matched server version — the client's patch applies wholesale.
    case applied(mergedFields: [String: AnyCodable], version: Int)
    /// Versions diverged but fields were reconciled by last-writer-wins. `serverKept` lists the
    /// fields where the server value won (the client lost those); `mergedFields` is the field set
    /// the client should now hold locally.
    case merged(mergedFields: [String: AnyCodable], serverKept: Set<String>, version: Int)
    /// A structural conflict (delete-vs-edit). Per the default rule, delete wins over edit; the app
    /// must surface this in the activity log rather than dropping it (ApiSpec §6.1).
    case structuralConflict(reason: StructuralConflictReason)

    public enum StructuralConflictReason: String, Equatable, Sendable {
        /// Client tried to upsert an entity the server has tombstoned.
        case upsertOnDeleted
        /// Client tried to delete an entity that the server resurrected/edited after the client's base.
        case deleteOnResurrected
    }
}

/// Metadata the resolver needs about one field's last write, for field-level LWW (ApiSpec §6.1
/// `field_meta`). The server keeps `{ v, updatedAt }` per field; the client mirrors `updatedAt` to
/// decide who wins a given field.
public struct FieldMeta: Equatable, Sendable {
    public var updatedAt: Date
    public init(updatedAt: Date) {
        self.updatedAt = updatedAt
    }
}

/// A pure, framework-free implementation of DoIT's last-writer-wins conflict resolution
/// (AppSpec §8, ApiSpec §6.1). No `Date()` calls, no I/O — every input is supplied by the caller so
/// the logic is fully deterministic and unit-testable (AppSpec §16).
///
/// Two strategies, matching the server's tunable (ApiSpec §6.1 / §20 Q1):
/// - ``resolveRowLevel(...)`` — coarse LWW on a single row `updatedAt`. Used for non-`task` entities.
/// - ``resolveFieldLevel(...)`` — per-field LWW using `field_meta`. Used for `tasks`, where
///   concurrent edits to different fields are common and should both survive.
public struct ConflictResolver: Sendable {
    public init() {}

    // MARK: Structural

    /// Detect a structural (delete-vs-edit) conflict before attempting field merges.
    /// Returns `nil` when there is no structural conflict and a value merge can proceed.
    public func structuralConflict(
        clientOp: SyncOp,
        serverIsDeleted: Bool,
        clientBaseVersion: Int,
        serverVersion: Int
    ) -> ConflictOutcome.StructuralConflictReason? {
        switch clientOp {
        case .upsert where serverIsDeleted:
            // Client edited a row the server has since tombstoned → delete wins by default.
            return .upsertOnDeleted
        case .delete where !serverIsDeleted && serverVersion > clientBaseVersion:
            // Client deleted a row that someone else resurrected/edited after the client's base.
            return .deleteOnResurrected
        default:
            return nil
        }
    }

    // MARK: Row-level LWW

    /// Coarse last-writer-wins on a whole row. The newer `updatedAt` wins the entire field set.
    ///
    /// - Parameters:
    ///   - clientFields: the client's proposed patch.
    ///   - serverFields: the server's current value for those same fields.
    ///   - clientUpdatedAt: when the client made its change (UTC).
    ///   - serverUpdatedAt: when the server's current value was written (UTC).
    ///   - clientBaseVersion: server version the client last saw.
    ///   - serverVersion: the server's current version.
    public func resolveRowLevel(
        clientOp: SyncOp = .upsert,
        clientFields: [String: AnyCodable],
        serverFields: [String: AnyCodable],
        clientUpdatedAt: Date,
        serverUpdatedAt: Date,
        clientBaseVersion: Int,
        serverVersion: Int,
        serverIsDeleted: Bool = false
    ) -> ConflictOutcome {
        if let reason = structuralConflict(
            clientOp: clientOp,
            serverIsDeleted: serverIsDeleted,
            clientBaseVersion: clientBaseVersion,
            serverVersion: serverVersion
        ) {
            return .structuralConflict(reason: reason)
        }

        // Fast path: nobody wrote since the client's base → apply wholesale.
        if clientBaseVersion == serverVersion {
            return .applied(mergedFields: clientFields, version: serverVersion + 1)
        }

        // Conflict path: coarse LWW. Strictly-newer client wins the row; ties and older lose.
        if clientUpdatedAt > serverUpdatedAt {
            return .merged(mergedFields: clientFields, serverKept: [], version: serverVersion + 1)
        } else {
            let serverKept = Set(clientFields.keys)
            return .merged(mergedFields: serverFields, serverKept: serverKept, version: serverVersion + 1)
        }
    }

    // MARK: Field-level LWW

    /// Per-field last-writer-wins (ApiSpec §6.1). For each field in the client's patch, the client
    /// wins **iff** `clientUpdatedAt` is strictly newer than that field's server `field_meta`
    /// timestamp; otherwise the server value is kept and reported in `serverKept`.
    ///
    /// - Parameters:
    ///   - clientFields: the client's proposed patch.
    ///   - serverFields: the server's current value for those fields (used when the server wins one).
    ///   - serverFieldMeta: per-field last-write metadata from the server. A field absent here is
    ///     treated as never-written-by-anyone-else, so the client wins it.
    ///   - clientUpdatedAt: when the client made its change (UTC).
    ///   - clientBaseVersion / serverVersion: version guards.
    public func resolveFieldLevel(
        clientOp: SyncOp = .upsert,
        clientFields: [String: AnyCodable],
        serverFields: [String: AnyCodable],
        serverFieldMeta: [String: FieldMeta],
        clientUpdatedAt: Date,
        clientBaseVersion: Int,
        serverVersion: Int,
        serverIsDeleted: Bool = false
    ) -> ConflictOutcome {
        if let reason = structuralConflict(
            clientOp: clientOp,
            serverIsDeleted: serverIsDeleted,
            clientBaseVersion: clientBaseVersion,
            serverVersion: serverVersion
        ) {
            return .structuralConflict(reason: reason)
        }

        if clientBaseVersion == serverVersion {
            return .applied(mergedFields: clientFields, version: serverVersion + 1)
        }

        var merged: [String: AnyCodable] = [:]
        var serverKept: Set<String> = []

        for (field, clientValue) in clientFields {
            if let meta = serverFieldMeta[field] {
                if clientUpdatedAt > meta.updatedAt {
                    merged[field] = clientValue            // client wrote later → client wins
                } else {
                    serverKept.insert(field)               // server wrote at/after → server wins
                    if let serverValue = serverFields[field] {
                        merged[field] = serverValue
                    }
                }
            } else {
                // No competing server write recorded for this field → client wins.
                merged[field] = clientValue
            }
        }

        if serverKept.isEmpty {
            // Client won every field; semantically equivalent to a clean apply at the new version.
            return .merged(mergedFields: merged, serverKept: [], version: serverVersion + 1)
        }
        return .merged(mergedFields: merged, serverKept: serverKept, version: serverVersion + 1)
    }
}
