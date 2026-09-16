import Foundation

/// A single to-do entry shown in the menu bar popover.
public struct TaskItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var isDone: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, isDone: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
    }
}
