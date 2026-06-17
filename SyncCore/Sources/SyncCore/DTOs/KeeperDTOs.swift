import Foundation

/// Wire DTOs for the Keeper feature (notes organized by folder; added feature, see DevelopmentPlan §10.5). Synced like any other
/// entity — payloads are RFC3339-normalized server-side (`iso()`), so timestamps decode as `Date`.

public struct NoteFolderDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var name: String
    public var colorHex: String
    public var icon: String
    public var sortIndex: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var serverVersion: Int
    public var deletedAt: Date?

    public init(id: String, ownerId: String, name: String, colorHex: String, icon: String,
                sortIndex: Int, createdAt: Date, updatedAt: Date,
                serverVersion: Int = 0, deletedAt: Date? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }
}

public struct NoteDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var folderId: String?
    /// Optional link to a task (Keeper task-note linking). Synthesized Codable treats this Optional as
    /// decode-if-present, so payloads written before the field existed decode to nil.
    public var taskId: String?
    public var title: String
    public var body: String
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var serverVersion: Int
    public var deletedAt: Date?

    public init(id: String, ownerId: String, folderId: String?, taskId: String? = nil,
                title: String, body: String,
                pinned: Bool, createdAt: Date, updatedAt: Date,
                serverVersion: Int = 0, deletedAt: Date? = nil) {
        self.id = id
        self.ownerId = ownerId
        self.folderId = folderId
        self.taskId = taskId
        self.title = title
        self.body = body
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }
}
