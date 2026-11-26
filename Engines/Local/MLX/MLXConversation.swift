import Foundation

/// A chat split the way `ChatSession` wants it: system instructions, earlier turns, and the message to answer.
struct MLXConversation: Equatable, Sendable {
    var instructions: String?
    var history: [PromptMessage]
    var prompt: String

    static func split(messages: [ChatMessage], systemPrompt: String?) throws -> MLXConversation {
        let all = PromptBuilder.promptMessages(from: messages, systemPrompt: systemPrompt)
        let system = all.filter { $0.role == "system" }.map(\.content)
        let turns = all.filter { $0.role != "system" }
        guard let last = turns.last else { throw MLXError.emptyConversation }
        return MLXConversation(
            instructions: system.isEmpty ? nil : system.joined(separator: "\n\n"),
            history: Array(turns.dropLast()),
            prompt: last.content)
    }
}
