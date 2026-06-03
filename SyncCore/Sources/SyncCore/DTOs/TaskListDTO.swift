import Foundation

/// Wire representation of a list/project. Mirrors the server `task_lists` table (ApiSpec §5.3) and
/// the SwiftData `TaskList` `@Model` (AppSpec §6). A "list" is the project shown in the Lists tab.
public struct TaskListDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var name: String
    public var colorHex: String
    /// SF Symbol name.
    public var icon: String
    public var sortIndex: Int
    /// Non-nil when the list is collaborative (-> a `Share`).
    public var shareId: String?

    public var createdAt: Date
    public var updatedAt: Date
    public var serverVersion: Int
    public var deletedAt: Date?

    public init(
        id: String,
        ownerId: String,
        name: String,
        colorHex: String,
        icon: String,
        sortIndex: Int = 0,
        shareId: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.sortIndex = sortIndex
        self.shareId = shareId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }
}
