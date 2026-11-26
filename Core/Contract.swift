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
}

/// Dropping the consumer Task must stop generation; implementations use `continuation.onTermination`.
protocol ChatEngine: Sendable {
    var source: ModelSource { get }
    func availableModels() async throws -> [ModelDescriptor]
    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error>
}
