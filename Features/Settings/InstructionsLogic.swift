import Foundation

/// Custom instructions: what a model is told before the conversation. One global text in Settings, and an optional
/// text for a single chat that replaces it.
enum InstructionsLogic {
    struct Template: Identifiable, Equatable, Sendable {
        var id: String
        var title: String
        var text: String
    }

    static let templates: [Template] = [
        Template(id: "concise", title: "Concise",
                 text: "Answer briefly and directly. Skip preambles and repeated summaries. Use short sentences, and a short list only when it helps."),
        Template(id: "teacher", title: "Teacher",
                 text: "Explain like a patient teacher. Start with the simple idea, then add detail step by step, use one concrete example, and end with a short question that checks understanding."),
        Template(id: "vietnamese", title: "Vietnamese replies",
                 text: "Always reply in Vietnamese, even when I write in another language, unless I ask for a different language. Keep names, code and quoted text as they are."),
        Template(id: "reviewer", title: "Code reviewer",
                 text: "Act as a careful code reviewer. List bugs and risks first, ordered by severity, then smaller style points. Quote the exact lines you mean and suggest a fix for each. Say so when the code looks fine."),
    ]

    /// Beyond this many characters the note warns that small on-device models lose room for the conversation.
    static let longLimit = 1500

    /// What a chat sends: this chat's own instructions, else the global ones, else none. Blank text counts as none.
    static func effective(chat: String?, global: String) -> String? {
        for candidate in [chat ?? "", global] {
            let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    /// A template added to what is written: it fills an empty editor, goes after existing text with a blank line,
    /// and is not added twice.
    static func inserting(_ template: Template, into text: String) -> String {
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty { return template.text }
        if current.contains(template.text) { return text }
        return current + "\n\n" + template.text
    }

    /// "182 characters", with a warning once the text is long.
    static func countText(_ text: String) -> String {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let base = "\(count) \(count == 1 ? "character" : "characters")"
        return count > longLimit ? base + ". Long for small on-device models." : base
    }

    /// Which models use the text. Every engine passes it on, so the answer is all of them; the default is named.
    static func usageNote(hasInstructions: Bool, defaultModelName: String?) -> String {
        guard hasInstructions else { return "Nothing is added. Every model answers with its own defaults." }
        guard let defaultModelName else { return "Used by every model: Apple Intelligence, on-device models and AnyRouter models." }
        return "Used by every model: \(defaultModelName) (your default), Apple Intelligence, on-device models and AnyRouter models."
    }

    /// The small tag in a chat's header when it has its own instructions.
    static func headerTag(chat: String?) -> String? {
        guard let chat, !chat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return "Custom instructions"
    }

    /// One line under the Custom instructions row in Response Customization.
    static func summary(global: String) -> String {
        let text = global.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Off" }
        return text.count > 40 ? String(text.prefix(40)) + "…" : text
    }
}
