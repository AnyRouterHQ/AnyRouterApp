import Foundation

enum ModelSource: String, Codable, Sendable { case apple, gguf, mlx, anyrouter }

struct ModelDescriptor: Identifiable, Hashable, Codable, Sendable {
    /// "apple/foundation", "gguf/<hf-repo>/<file>", "mlx/<hf-repo>", "anyrouter/<provider/model>"
    var id: String
    var source: ModelSource
    var displayName: String
    var contextLength: Int?
    /// "chat", "vision", "tools", ...
    var capabilities: Set<String>
    /// Local models only.
    var sizeBytes: Int64?
    /// Remote and Apple models: true when usable.
    var isInstalled: Bool
    /// One-line description from the provider, when it has one.
    var summary: String? = nil
}

struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case system, user, assistant }
    var id: UUID
    var role: Role
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct GenerationParams: Codable, Sendable {
    var temperature: Double = 0.7
    var topP: Double = 0.95
    var maxTokens: Int? = nil
    var systemPrompt: String? = nil
}

enum ChatDelta: Sendable, Equatable {
    /// Append-only suffix.
    case text(String)
    case usage(prompt: Int, completion: Int)
    case done(finishReason: String?)
    /// The model asked for a tool. Emitted once per call, before it runs.
    case toolCall(ToolCall)
    /// Outcome of a call the engine ran through its `ToolHost`.
    case toolResult(ToolResult)
}

/// Dropping the consumer Task must stop generation; implementations use `continuation.onTermination`.
protocol ChatEngine: Sendable {
    var source: ModelSource { get }
    func availableModels() async throws -> [ModelDescriptor]
    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error>
    /// Same, with tools the model may call. Engines that cannot call tools keep the default, which
    /// ignores `tools` and streams plain text.
    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?)
        -> AsyncThrowingStream<ChatDelta, Error>
}

extension ChatEngine {
    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?)
        -> AsyncThrowingStream<ChatDelta, Error> {
        stream(model: model, messages: messages, params: params)
    }
}
