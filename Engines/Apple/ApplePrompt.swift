import Foundation

/// Turns a chat history into what the on-device model takes: instructions plus one prompt.
/// Kept free of FoundationModels so it is testable anywhere.
enum ApplePrompt {
    struct Built: Equatable {
        var instructions: String?
        var prompt: String
    }

    enum Failure: Error, Equatable {
        case noUserMessage
    }

    static func build(messages: [ChatMessage], params: GenerationParams) throws -> Built {
        var instructions: [String] = []
        if let system = params.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !system.isEmpty {
            instructions.append(system)
        }
        var turns: [ChatMessage] = []
        for message in messages {
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if message.role == .system {
                instructions.append(text)
            } else {
                var copy = message
                copy.content = text
                turns.append(copy)
            }
        }
        guard let last = turns.last, last.role == .user else { throw Failure.noUserMessage }
        let prompt: String
        if turns.count == 1 {
            prompt = last.content
        } else {
            // Replay earlier turns as a labelled transcript; the model answers the last user turn.
            prompt = turns.map { turn in
                (turn.role == .user ? "User: " : "Assistant: ") + turn.content
            }.joined(separator: "\n\n")
        }
        return Built(
            instructions: instructions.isEmpty ? nil : instructions.joined(separator: "\n\n"),
            prompt: prompt
        )
    }
}
