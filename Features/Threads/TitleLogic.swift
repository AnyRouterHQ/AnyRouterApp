import Foundation

/// What to ask for a chat's title, whether and where to ask it, and how to clean the answer. Pure: the chat only runs the request.
struct TitlePlan: Equatable {
    var model: ModelDescriptor
    var system: String
    var messages: [ChatMessage]
}

enum TitleLogic {
    /// The title is asked to stay this short.
    static let maxTokens = 24
    static let maxLength = 60
    /// Each side of the exchange is cut to this many characters in the request, so a small window is enough.
    static let maxExcerpt = 500

    static let systemPrompt = """
        You write the title of a chat from its first exchange. Reply with the title only: 2 to 6 words, in the language \
        the user wrote in, no quotes, no period at the end.
        """

    /// The request, or nil when no title should be asked now: only a title still taken from the first message is
    /// replaced, and only once there is a reply to read.
    static func plan(
        source: TitleSource, messages: [ChatMessage], chat: ModelDescriptor, models: [ModelDescriptor], isOnline: Bool
    ) -> TitlePlan? {
        guard source == .firstMessage, let reply = messages.first(where: { $0.role == .assistant && !isBlank($0.content) }) else { return nil }
        guard let model = engineModel(chat: chat, models: models, isOnline: isOnline) else { return nil }
        let question = messages.first { $0.role == .user && !isBlank($0.content) }
        let parts: [String?] = [question.map { "User: " + excerpt($0.content) }, "Assistant: " + excerpt(reply.content)]
        let text = "Conversation:\n" + parts.compactMap { $0 }.joined(separator: "\n") + "\n\nTitle:"
        return TitlePlan(model: model, system: systemPrompt, messages: [ChatMessage(role: .user, content: text)])
    }

    /// The model that writes the title. Apple's on-device model when it is ready, so the text of a chat stays on the
    /// device even when the chat itself is in the cloud. Otherwise the chat's own model: a local chat stays local, and
    /// a cloud chat needs the connection. A device chat's text is never sent to the cloud for a title.
    static func engineModel(chat: ModelDescriptor, models: [ModelDescriptor], isOnline: Bool) -> ModelDescriptor? {
        if let apple = models.first(where: { $0.source == .apple && $0.isInstalled }) { return apple }
        return OfflineLogic.needsNetwork(chat) && !isOnline ? nil : chat
    }

    /// The title from the model's raw answer: no thinking, one line, no label, no quotes, no closing period, short.
    /// Nil when nothing is left.
    static func clean(_ raw: String) -> String? {
        var splitter = ReasoningSplitter()
        let answer = splitter.feed(raw).text + splitter.finish().text
        guard let line = answer.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else { return nil }
        var title = Substring(line)
        if title.lowercased().hasPrefix("title:") { title = title.dropFirst("title:".count) }
        let lead = Set("\"'`*#“”‘’«» ")
        let trail = lead.union(".。")
        while let first = title.first, lead.contains(first) { title.removeFirst() }
        while let last = title.last, trail.contains(last) { title.removeLast() }
        if title.count > maxLength { title = title.prefix(maxLength) }
        let result = String(title).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : result
    }

    private static func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private static func excerpt(_ text: String) -> String { String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxExcerpt)) }
}
