import Foundation

/// How photos reach a local GGUF model: the rules around llama.cpp's `mtmd`, with no C calls so they are testable.
enum VisionInput {
    /// What llama.cpp's `mtmd` reads as "an image goes here" in the prompt text.
    static let defaultMarker = "<__media__>"
    /// Longest image side when the catalog says nothing.
    static let defaultImageSide = 1024
    /// Photos sent with one message. More cost memory and time on a phone; the rest are named in the text.
    static let maxImages = 4
    /// Tokens one photo takes in the context, a rule of thumb used to leave room before the prompt is built.
    static let tokensPerImage = 600

    /// Whether a downloaded file is a vision projector.
    static func isProjector(path: String) -> Bool {
        (path as NSString).lastPathComponent.lowercased().contains("mmproj")
    }

    /// The longest side to feed the projector: the catalog's value, kept within sensible bounds.
    static func imageSide(for vision: CatalogVision?) -> Int {
        min(max(vision?.imageSide ?? defaultImageSide, 224), 4096)
    }

    /// The prompt for a model that sees photos. Only the photos of the last user message go in as images, each as a
    /// marker in its text, newest `maxImages` of them; photos of earlier turns stay as the text read from them.
    static func prompt(
        from messages: [ChatMessage], systemPrompt: String?, marker: String = defaultMarker
    ) -> (messages: [PromptMessage], images: [ChatAttachment]) {
        var prompt = PromptBuilder.promptMessages(from: messages, systemPrompt: systemPrompt)
        guard let lastUser = messages.lastIndex(where: { $0.role == .user }),
              messages[lastUser].attachments.contains(where: { $0.kind == .image })
        else { return (prompt, []) }
        let message = messages[lastUser]
        let all = message.attachments.filter { $0.kind == .image }
        let sent = Array(all.suffix(maxImages))
        var text = AttachmentPrompt.text(for: message, sendsImages: true)
        let omitted = all.count - sent.count
        if omitted > 0 { text = "[\(omitted) more image\(omitted == 1 ? "" : "s") not sent: at most \(maxImages) at a time.]\n" + text }
        let markers = sent.map { _ in marker }.joined(separator: "\n")
        // The prompt list may start with a system message the builder added: the user message is the one with this text.
        let offset = prompt.count - messages.count
        let position = lastUser + max(0, offset)
        if prompt.indices.contains(position) {
            prompt[position].content = text.isEmpty ? markers : markers + "\n" + text
        }
        return (prompt, sent)
    }
}
