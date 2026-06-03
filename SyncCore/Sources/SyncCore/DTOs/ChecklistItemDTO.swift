import Foundation

/// Wire representation of a checklist (sub-task) item under a task (ApiSpec §5.7). Mirrors the server
/// `checklist_items` row + the SwiftData `ChecklistItem` `@Model`.
public struct ChecklistItemDTO: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var ownerId: String
    public var taskId: String
    public var text: String
    public var done: Bool
    /// Sort order within the task's checklist.
    public var ord: Int

    public var createdAt: Date
    public var updatedAt: Date
    public var serverVersion: Int
    public var deletedAt: Date?

    public init(
        id: String,
        ownerId: String,
        taskId: String,
        text: String,
        done: Bool = false,
        ord: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        serverVersion: Int = 0,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.ownerId = ownerId
        self.taskId = taskId
        self.text = text
        self.done = done
        self.ord = ord
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverVersion = serverVersion
        self.deletedAt = deletedAt
    }
}
