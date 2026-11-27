import Foundation

extension ChatViewModel {
    /// A quick action on copied text or a link: the prompt and the copy go out at once, with the clipboard badge.
    /// The caller reads the clipboard in the person's own tap.
    @discardableResult
    func quickSend(_ preset: PromptPreset, text: String, deviceLanguage: String) -> Task<Void, Never>? {
        nextSendFromClipboard = true
        let task: Task<Void, Never>?
        if preset.action == .summarizeLink {
            task = run(.summarizeLink, clipboardText: { text })
        } else if let prompt = ClipboardQuickSend.prompt(preset, text: text, deviceLanguage: deviceLanguage) {
            fill(prompt)
            task = send()
        } else {
            task = nil
        }
        if task == nil { nextSendFromClipboard = false }
        return task
    }

    /// A quick action on a copied image: it is attached, then the prompt goes out with it.
    @discardableResult
    func quickSend(_ preset: PromptPreset, image: Data) -> Task<Void, Never> {
        attachImages([(data: image, filename: "Clipboard.png")])
        return Task { [weak self] in
            guard let self else { return }
            await finishIngesting()
            nextSendFromClipboard = true
            fill(preset.prompt)
            if let sent = send() { await sent.value } else { nextSendFromClipboard = false }
        }
    }
}
