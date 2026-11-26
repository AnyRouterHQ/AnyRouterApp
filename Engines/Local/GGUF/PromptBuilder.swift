import Foundation

struct PromptMessage: Equatable, Sendable {
    var role: String
    var content: String
}

enum PromptBuilder {
    /// Core messages as role/content pairs. `systemPrompt` is prepended unless the conversation already starts with a system message.
    static func promptMessages(from messages: [ChatMessage], systemPrompt: String?) -> [PromptMessage] {
        var result = messages.map { PromptMessage(role: $0.role.rawValue, content: $0.content) }
        if let systemPrompt, !systemPrompt.isEmpty, result.first?.role != "system" {
            result.insert(PromptMessage(role: "system", content: systemPrompt), at: 0)
        }
        return result
    }

    /// Drops the oldest user/assistant turns until `fits` is true. System messages and the last message stay.
    /// Returns nil when even the system messages plus the last message do not fit.
    static func trimmed(_ messages: [PromptMessage], fits: ([PromptMessage]) throws -> Bool) rethrows -> [PromptMessage]? {
        var current = messages
        while try !fits(current) {
            guard let oldest = current.indices.dropLast().first(where: { current[$0].role != "system" }) else { return nil }
            current.remove(at: oldest)
        }
        return current
    }
}

/// Fallback when a model ships no chat template llama.cpp can apply.
enum ChatMLFormatter {
    static func format(_ messages: [PromptMessage]) -> String {
        var text = ""
        for message in messages {
            text += "<|im_start|>\(message.role)\n\(message.content)<|im_end|>\n"
        }
        return text + "<|im_start|>assistant\n"
    }
}

/// Collects token bytes and releases only complete UTF-8 text, so an emoji split across tokens is never shown as garbage.
struct UTF8Accumulator {
    private var pending: [UInt8] = []

    /// Adds bytes. Returns the text that is complete so far, or nil when nothing is yet.
    mutating func append(_ bytes: [UInt8]) -> String? {
        pending.append(contentsOf: bytes)
        // A UTF-8 character is at most 4 bytes, so at most 3 trailing bytes can be an unfinished one.
        for cut in 0...min(3, pending.count) {
            let head = pending.dropLast(cut)
            if let text = String(validating: head, as: UTF8.self) {
                pending = Array(pending.suffix(cut))
                return text.isEmpty ? nil : text
            }
        }
        // Invalid bytes in the middle: pass them through lossy rather than stall the stream.
        let text = String(decoding: pending, as: UTF8.self)
        pending = []
        return text
    }

    /// Whatever is left at the end of the stream, decoded lossily.
    mutating func flush() -> String? {
        defer { pending = [] }
        return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
    }
}
