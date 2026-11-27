import Foundation

/// A chat's one summary in memory (agent design 2.3, unit M6): what search_chats shows and what recall finds in other
/// chats. Written when the chat loses focus, at most once per change of the chat.
struct ChatSummaryPlan: Equatable {
    var model: ModelDescriptor
    var system: String
    var messages: [ChatMessage]
}

enum ChatSummaryLogic {
    /// Shorter chats say too little to be worth finding.
    static let minimumMessages = 6
    static let maxTokens = 160
    /// The newest messages the request carries, each cut short, so Apple's 4,096-token window is enough.
    static let maxMessages = 12
    static let maxExcerpt = 300

    static let systemPrompt = """
        You summarize a chat so it can be found later. In at most three plain sentences, say what it was about, what was \
        decided, and the names, places, numbers and preferences the user gave. Reply with the summary only.
        """

    enum Action: Equatable {
        case skip
        /// The chat was shortened before: its compaction summary is the chat summary, no model call.
        case store(String)
        case ask(ChatSummaryPlan)
    }

    /// The model is D30's: Apple's on-device model when ready, else the chat's own, never a cloud model for a device
    /// chat. A model on GGUF or MLX is never asked: a second generation would hold the one loaded model.
    static func action(
        messages: [ChatMessage], compactionSummary: String?, summarizedAt: Date?, changedAt: Date,
        chat: ModelDescriptor, models: [ModelDescriptor], isOnline: Bool
    ) -> Action {
        guard messages.count >= minimumMessages, summarizedAt.map({ $0 < changedAt }) ?? true else { return .skip }
        if let compactionSummary { return .store(String(compactionSummary.prefix(MemoryKind.chatSummary.textLimit))) }
        guard let model = TitleLogic.engineModel(chat: chat, models: models, isOnline: isOnline),
              model.source != .gguf, model.source != .mlx else { return .skip }
        let lines = messages.suffix(maxMessages).map { message in
            (message.role == .user ? "User: " : "Assistant: ") + String(message.content.prefix(maxExcerpt))
        }
        let text = "Conversation:\n" + lines.joined(separator: "\n") + "\n\nSummary:"
        return .ask(ChatSummaryPlan(model: model, system: systemPrompt, messages: [ChatMessage(role: .user, content: text)]))
    }

    /// The summary from the model's answer: no thinking, no label, trimmed and capped. Nil when nothing is left.
    static func clean(_ raw: String) -> String? {
        var splitter = ReasoningSplitter()
        var text = (splitter.feed(raw).text + splitter.finish().text).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("summary:") { text = String(text.dropFirst("summary:".count)).trimmingCharacters(in: .whitespaces) }
        return text.isEmpty ? nil : String(text.prefix(MemoryKind.chatSummary.textLimit))
    }

    /// Where the summary may go: a chat any of whose replies came from this device stays off cloud models.
    static func scope(replyModelIDs: [String?]) -> MemoryScope {
        MemoryToolLogic.isCloudChat(replyModelIDs: replyModelIDs) ? .everywhere : .deviceOnly
    }
}
