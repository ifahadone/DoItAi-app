import Foundation

/// Wire DTOs for sharing & collaboration (ApiSpec §7.7). Timestamps are kept as `String?` because the
/// sharing/comment endpoints return raw rows (Postgres timestamp text, not RFC3339) — the UI displays
/// them as-is and never needs to parse them for correctness.

public struct ShareDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var listId: String
    public var ownerId: String
    public var createdAt: String?
    public var deletedAt: String?
}

public struct ShareMemberDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var shareId: String
    public var userId: String
    public var role: String
    public var joinedAt: String?
}

public struct InviteDTO: Codable, Sendable, Equatable {
    public var token: String
    public var role: String
    public var acceptPath: String
}

public struct CommentDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var taskId: String
    public var body: String
    public var mentions: [String]?
    public var createdAt: String?
}

/// One parsed realtime envelope from the WebSocket (ApiSpec §8). Only `sync.bump` is acted on; the rest
/// are advisory.
public enum RealtimeEvent: Sendable, Equatable {
    case ready
    case bump(cursor: String?)
    case other(String)

    public static func parse(_ text: String) -> RealtimeEvent? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return nil }
        switch type {
        case "ready": return .ready
        case "sync.bump":
            let cursor = (obj["data"] as? [String: Any])?["cursor"] as? String
            return .bump(cursor: cursor)
        default: return .other(type)
        }
    }
}
