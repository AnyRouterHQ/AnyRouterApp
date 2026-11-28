import Foundation
import SwiftData

/// Where a thread's title came from. A title the user set is never replaced.
enum TitleSource: String, Sendable {
    /// The first message, cut to length. A generated title may replace it.
    case firstMessage
    case generated
    case user
}

@Model
final class ThreadRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    /// `ModelDescriptor.id` last used in this thread.
    var modelID: String?
    /// "Enable thinking" for this thread. Engines read it once reasoning is wired.
    var thinkingEnabled: Bool = false
    /// Agent mode is off for this thread. Tools are on unless the user turned them off here.
    var toolsDisabled: Bool = false
    /// Instructions for this chat only. They replace the global custom instructions. Optional so existing stores migrate.
    var instructions: String?
    /// Stretches of this chat folded into summaries, as JSON. The messages stay. Optional so existing stores migrate.
    var compactionData: Data?
    /// Messages typed while a reply streamed, as JSON (`MessageQueue`). Optional so existing stores migrate.
    var queueData: Data?
    /// `TitleSource` raw value. Optional so existing stores migrate; a chat stored before titles had a source counts as the user's.
    var titleSourceRaw: String?
    /// Ids of the memory items this chat puts in its prompt, as JSON, frozen at its first send (agent design 2.4).
    /// Optional so existing stores migrate.
    var profileSnapshotData: Data?
    /// "Don't use memory in this chat".
    var memoryOff: Bool = false
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

    var titleSource: TitleSource {
        get { titleSourceRaw.flatMap(TitleSource.init(rawValue:)) ?? .user }
        set { titleSourceRaw = newValue.rawValue }
    }

    var queue: MessageQueue {
        get { queueData.flatMap { try? JSONDecoder().decode(MessageQueue.self, from: $0) } ?? MessageQueue() }
        set { queueData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var profileSnapshot: [UUID]? {
        get { profileSnapshotData.flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } }
        set { profileSnapshotData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var compactions: [Compaction] {
        get { compactionData.flatMap { try? JSONDecoder().decode([Compaction].self, from: $0) } ?? [] }
        set { compactionData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    /// Messages in creation order, as a model reads them. A failed reply with no text is left out: it holds nothing to read.
    var orderedMessages: [ChatMessage] {
        messages.filter { $0.failureData == nil || !$0.content.isEmpty }.sorted { $0.createdAt < $1.createdAt }.map(\.chatMessage)
    }
}

@Model
final class MessageRecord {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var thread: ThreadRecord?
    /// Tool calls of an assistant reply as JSON. Display only: it is never sent back to a model.
    /// Optional so existing stores migrate without a mapping.
    var toolTraceData: Data?
    /// What the model thought before it answered, as JSON. Display only. Optional so existing stores migrate without a mapping.
    var reasoningData: Data?
    /// Who served this reply, cost and speed, as JSON. Optional so existing stores migrate without a mapping.
    var metadataData: Data?
    /// Display name of the model that wrote this reply. Optional so existing stores migrate.
    var modelName: String?
    /// Id of that model, for its logo and for "Switched to" notes.
    var modelID: String?
    /// Attachments of a user message as JSON. Optional so existing stores migrate without a mapping.
    var attachmentsData: Data?
    /// Where a user message came from: `clipboardOrigin` for a quick action on a copy. Optional so existing stores migrate.
    var origin: String?
    /// Why this reply did not finish, as JSON. Optional so existing stores migrate without a mapping.
    var failureData: Data?
    /// What this turn saved to memory, as JSON (`MemoryUpdate`). Optional so existing stores migrate.
    var memoryUpdatesData: Data?
    /// The memories recalled for this reply's question, as JSON (`MemoryHit`). Optional so existing stores migrate.
    var memoryHitsData: Data?

    static let clipboardOrigin = "clipboard"
    var fromClipboard: Bool { origin == Self.clipboardOrigin }

    init(id: UUID = UUID(), role: ChatMessage.Role, content: String, createdAt: Date = Date(),
         modelName: String? = nil, modelID: String? = nil) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.modelName = modelName
        self.modelID = modelID
    }

    convenience init(_ message: ChatMessage) {
        self.init(id: message.id, role: message.role, content: message.content, createdAt: message.createdAt)
        self.attachments = message.attachments
    }

    var role: ChatMessage.Role {
        get { ChatMessage.Role(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    var attachments: [ChatAttachment] {
        get { attachmentsData.flatMap { try? JSONDecoder().decode([ChatAttachment].self, from: $0) } ?? [] }
        set { attachmentsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var metadata: ResponseMetadata? {
        get { metadataData.flatMap { try? JSONDecoder().decode(ResponseMetadata.self, from: $0) } }
        set { metadataData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var reasoning: ReasoningTrace? {
        get { reasoningData.flatMap { try? JSONDecoder().decode(ReasoningTrace.self, from: $0) } }
        set { reasoningData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    /// Nil for every reply that finished, without decoding anything.
    var failure: ReplyFailure? {
        get { failureData.flatMap { try? JSONDecoder().decode(ReplyFailure.self, from: $0) } }
        set { failureData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var memoryHits: [MemoryHit] {
        get { memoryHitsData.flatMap { try? JSONDecoder().decode([MemoryHit].self, from: $0) } ?? [] }
        set { memoryHitsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var memoryUpdates: [MemoryUpdate] {
        get { memoryUpdatesData.flatMap { try? JSONDecoder().decode([MemoryUpdate].self, from: $0) } ?? [] }
        set { memoryUpdatesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var toolSteps: [ToolStep] {
        get { toolTraceData.flatMap { try? JSONDecoder().decode([ToolStep].self, from: $0) } ?? [] }
        set { toolTraceData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var chatMessage: ChatMessage {
        ChatMessage(id: id, role: role, content: content, createdAt: createdAt, attachments: attachments)
    }
}

extension ModelContainer {
    /// Schema shared by the app and tests.
    static func anyRouter(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let configuration = storeURL.map { ModelConfiguration(url: $0) } ?? ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: ThreadRecord.self, MessageRecord.self, DecisionRunRecord.self, MemoryRecord.self, AgentRunRecord.self, SkillRecord.self,
            configurations: configuration
        )
    }
}
