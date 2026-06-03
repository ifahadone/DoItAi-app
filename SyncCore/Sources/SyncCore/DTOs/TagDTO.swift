import Foundation

/// Wire representation of a tag. Mirrors the server `tags` table (ApiSpec §5.3) and the SwiftData
/// `Tag` `@Model` (AppSpec §6). Tags relate to tasks M:N (server `task_tags`); on a task the
/// relationship is carried as ``TaskDTO/tagIds``.
public struct TagDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var name: String
    public var colorHex: String

    public var createdAt: Date
    public var updatedAt: Date
    public var serverVersion: Int
    public var deletedAt: Date?

    public init(
        id: String,
        ownerId: String,
        name: String,
        colorHex: String,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }
}
