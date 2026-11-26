import Foundation
import Observation

/// Preset ids the entry points (Shortcuts, Siri, Control Center, the Share sheet) rely on.
enum InboundPreset {
    static let fixEnglish = "fix-english"
}

/// A request from outside the chat to open a fresh one: text for the composer, a preset to apply, and whether to send.
struct InboundChat: Identifiable, Equatable, Sendable {
    let id = UUID()
    var text: String?
    var presetID: String?
    var sendNow = false
}

enum InboundChatLogic {
    /// The composer text for a request. A preset prompt that ends in a line break ("Email:\n") takes the text right
    /// after it; any other preset prompt gets a blank line first, so the text reads as extra context.
    static func composerText(preset: PromptPreset?, text: String?) -> String {
        let body = trimmed(text)
        guard let preset else { return body }
        if body.isEmpty { return preset.prompt }
        let lead = preset.prompt.hasSuffix("\n") ? preset.prompt : preset.prompt + "\n\n"
        return lead + body
    }

    private static func trimmed(_ text: String?) -> String {
        guard let text else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
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
