import Foundation
import Observation

// Compiled into the app and into the controls extension, so a control's intent can leave a request for the app
// without the extension knowing anything else about the app.

/// Preset ids the entry points (Shortcuts, Siri, Control Center, the Share sheet) rely on.
enum InboundPreset {
    static let fixEnglish = "fix-english"
    static let summarize = "summarize"
    static let translate = "translate"
}

/// A request from outside the chat to open a fresh one: text for the composer, a preset to apply, whether to send, and
/// whether to ask for the text first (a control cannot read the clipboard, so the chat shows a Paste button).
struct InboundChat: Identifiable, Equatable, Sendable {
    let id = UUID()
    var text: String?
    var presetID: String?
    var sendNow = false
    var asksForText = false
    /// Start dictating into the composer once the chat is open.
    var startsVoice = false
    /// Files (PDFs) to attach to the new chat.
    var files: [URL] = []
    /// Photos whose text is read on the device; the scan sheet then offers Translate, Split this bill and Summarize.
    var readsTextFrom: [URL] = []
}

/// Where App Intents leave a request. An intent runs in the app process but cannot reach the window's `ShellModel`,
/// and on a cold launch no window exists yet, so the root view picks the request up from here.
@MainActor @Observable
final class InboundChatMailbox {
    static let shared = InboundChatMailbox()

    private(set) var pending: InboundChat?

    func post(_ request: InboundChat) { pending = request }

    func take() -> InboundChat? {
        defer { pending = nil }
        return pending
    }
}
