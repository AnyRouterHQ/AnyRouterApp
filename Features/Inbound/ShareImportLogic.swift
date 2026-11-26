import Foundation

/// Turns what the share extension left (a payload in the App Group inbox, or a link) into a request for a fresh chat.
enum ShareImportLogic {
    /// The shared text and the link, one under the other. Nil when there is neither.
    static func text(of payload: SharedPayload) -> String? {
        let parts = [payload.text, payload.url].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    /// A preset with pickers asks for its choices first, with the shared text as the message. Without text there is
    /// nothing to ask about, so it just applies.
    static func request(text: String?, preset: PromptPreset?, pdfs: [URL] = [], images: [URL] = []) -> InboundChat {
        var request = InboundChat(text: text, presetID: preset?.id)
        request.asksForText = preset?.hasOptions == true && text != nil
        request.files = pdfs
        request.readsTextFrom = images
        return request
    }

    /// An `anyrouter://ask` link. Other links (`anyrouter://share`) are not requests.
    static func request(for url: URL, presets: PresetStore) -> InboundChat? {
        guard let link = ShareDeepLink.parse(url) else { return nil }
        return request(text: link.text, preset: link.action.presetID.flatMap { presets.preset(id: $0) })
    }

    /// The newest share waiting in the inbox becomes a request in the mailbox; older ones are dropped, because only
    /// the last thing shared is the one the person wants now. Its files move to `workDirectory` first.
    /// Returns whether a request was posted.
    @MainActor
    @discardableResult
    static func pickUp(inbox: ShareInbox, presets: PresetStore, mailbox: InboundChatMailbox, workDirectory: URL) -> Bool {
        let waiting = inbox.pending()
        guard let newest = waiting.last else { return false }
        waiting.dropLast().forEach { inbox.discard($0) }
        let folder: URL
        do {
            folder = try inbox.claim(newest, into: workDirectory)
        } catch {
            inbox.discard(newest)
            return false
        }
        let urls = { (kind: SharedFile.Kind) in newest.files.filter { $0.kind == kind }.map { folder.appending(path: $0.filename) } }
        let preset = newest.action.presetID.flatMap { presets.preset(id: $0) }
        mailbox.post(request(text: text(of: newest), preset: preset, pdfs: urls(.pdf), images: urls(.image)))
        return true
    }
}
