import Foundation

struct PromptMessage: Equatable, Sendable {
    var role: String
    var content: String
}

enum PromptBuilder {
    /// Whether tokenizing should add the vocabulary's own special tokens (BOS). Not when the prompt already starts with
    /// the BOS text, as Llama-style templates write it: the model would see two.
    static func addsSpecialTokens(to prompt: String, bosText: String?) -> Bool {
        guard let bosText, !bosText.isEmpty else { return true }
        return !prompt.hasPrefix(bosText)
    }

    /// Core messages as role/content pairs. `systemPrompt` is prepended unless the conversation already starts with a system message.
    static func promptMessages(from messages: [ChatMessage], systemPrompt: String?) -> [PromptMessage] {
        // Local models read attached files as text; photos arrive as the text OCR found in them.
        var result = messages.map {
            PromptMessage(role: $0.role.rawValue, content: AttachmentPrompt.text(for: $0, sendsImages: false))
        }
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

/// Gemma 4 turn format. Its GGUF template is jinja-only and newer than llama.cpp's built-in template list,
/// so `llama_chat_apply_template` rejects it and the ChatML fallback would be the wrong format.
/// No `<bos>` here: tokenizing the prompt adds it.
enum Gemma4Formatter {
    static func matches(template: String) -> Bool {
        template.contains("<|turn>") && template.contains("<turn|>")
    }

    static func format(_ messages: [PromptMessage]) -> String {
        var text = ""
        for message in messages {
            let role = message.role == "assistant" ? "model" : message.role
            text += "<|turn>\(role)\n\(message.content.trimmingCharacters(in: .whitespacesAndNewlines))<turn|>\n"
        }
        return text + "<|turn>model\n"
    }
}

/// Gemma 4 can open a thinking channel (`<|channel>thought ... <channel|>`) before its answer.
/// The app has no thinking view yet, so tokens inside the channel are not shown.
struct ThoughtChannelFilter {
    let open: Int32?
    let close: Int32?
    private var inside = false

    init(open: Int32?, close: Int32?) {
        self.open = open
        self.close = close
    }

    /// True when the token belongs to the visible answer. The channel markers themselves are never shown.
    mutating func isVisible(_ token: Int32) -> Bool {
        if let open, token == open {
            inside = true
            return false
        }
        if let close, token == close {
            inside = false
            return false
        }
        return !inside
    }
}

/// Collects token bytes and releases only complete UTF-8 text, so an emoji split across tokens is never shown as garbage.
struct UTF8Accumulator {
    private var pending: [UInt8] = []

    /// Adds bytes. Returns the text that is complete so far, or nil when nothing is yet.
    /// Only a trailing, still unfinished (but valid so far) character is held back; invalid bytes are replaced, not waited for.
    mutating func append(_ bytes: [UInt8]) -> String? {
        pending.append(contentsOf: bytes)
        let held = Self.unfinishedTailLength(pending)
        let ready = pending.dropLast(held)
        pending = Array(pending.suffix(held))
        return ready.isEmpty ? nil : String(decoding: ready, as: UTF8.self)
    }

    /// Whatever is left at the end of the stream, decoded lossily.
    mutating func flush() -> String? {
        defer { pending = [] }
        return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
    }

    /// Length of a trailing character that has its lead byte but not all its continuation bytes yet.
    private static func unfinishedTailLength(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
        for offset in 1...min(3, bytes.count) {
            let byte = bytes[bytes.count - offset]
            if byte & 0xC0 == 0x80 { continue } // continuation byte: keep looking for its lead
            let needed = byte >= 0xF8 ? 1 : byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
            return needed > offset ? offset : 0
        }
        return 0
    }
}
