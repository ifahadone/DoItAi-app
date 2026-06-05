import Foundation

// Integer-backed enums mirroring the server SMALLINT columns (ApiSpec §5.1) and AppSpec §6.
// The raw values are part of the wire contract — DO NOT reorder. New cases are appended only.

/// Task lifecycle state. Server `tasks.status` SMALLINT.
public enum TaskStatus: Int, Codable, Sendable, CaseIterable {
    case inbox = 0
    case scheduled = 1
    case inProgress = 2
    case done = 3
    case cancelled = 4
}

/// Task priority. Server `tasks.priority` SMALLINT. `none` is the default (0); `p1` is highest (4).
public enum Priority: Int, Codable, Sendable, CaseIterable {
    case none = 0
    case p4 = 1
    case p3 = 2
    case p2 = 3
    case p1 = 4
}

/// Energy required for a task. Server `tasks.energy` SMALLINT (nullable).
public enum Energy: Int, Codable, Sendable, CaseIterable {
    case low = 0
    case med = 1
    case high = 2
}

/// Sync operation kind for an outbox entry / push op (ApiSpec §6.1). String-valued on the wire.
public enum SyncOp: String, Codable, Sendable {
    case upsert
    case delete
}

/// Per-op result status returned by `POST /sync/push` (ApiSpec §6.1).
public enum PushStatus: String, Codable, Sendable {
    case applied
    case merged
    case conflict
    case rejected
    case duplicate
}

/// Entity types that flow through sync (ApiSpec §5.2 `change_log.entity_type`).
/// Modeled as a raw `String` enum with an `unknown` fallback so a newer server entity type does not
/// fail decoding on an older client (additive-contract rule, ApiSpec §13).
public enum SyncEntityType: RawRepresentable, Codable, Sendable, Equatable {
    case task
    case list
    case tag
    case routine
    case reminder
    case checklist
    case alarm
    case event
    case comment
    case noteFolder
    case note
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "task": self = .task
        case "list": self = .list
        case "tag": self = .tag
        case "routine": self = .routine
        case "reminder": self = .reminder
        case "checklist": self = .checklist
        case "alarm": self = .alarm
        case "event": self = .event
        case "comment": self = .comment
        case "noteFolder": self = .noteFolder
        case "note": self = .note
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .task: return "task"
        case .list: return "list"
        case .tag: return "tag"
        case .routine: return "routine"
        case .reminder: return "reminder"
        case .checklist: return "checklist"
        case .alarm: return "alarm"
        case .event: return "event"
        case .comment: return "comment"
        case .noteFolder: return "noteFolder"
        case .note: return "note"
        case .unknown(let value): return value
        }
    }
}
