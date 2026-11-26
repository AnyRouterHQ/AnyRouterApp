import Foundation
import SwiftData

@Model
final class ThreadRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    /// `ModelDescriptor.id` last used in this thread.
    var modelID: String?
    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.thread)
    var messages: [MessageRecord] = []

    init(id: UUID = UUID(), title: String = "New chat", createdAt: Date = Date(),
         isPinned: Bool = false, modelID: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.isPinned = isPinned
        self.modelID = modelID
    }

    /// Messages in creation order.
    var orderedMessages: [ChatMessage] {
        messages.sorted { $0.createdAt < $1.createdAt }.map(\.chatMessage)
    }
}

@Model
final class MessageRecord {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var thread: ThreadRecord?

    init(id: UUID = UUID(), role: ChatMessage.Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
    }

    convenience init(_ message: ChatMessage) {
        self.init(id: message.id, role: message.role, content: message.content, createdAt: message.createdAt)
    }

    var role: ChatMessage.Role {
        get { ChatMessage.Role(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    var chatMessage: ChatMessage {
        ChatMessage(id: id, role: role, content: content, createdAt: createdAt)
    }
}

extension ModelContainer {
    /// Schema shared by the app and tests.
    static func anyRouter(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(
            for: ThreadRecord.self, MessageRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory)
        )
    }
}
