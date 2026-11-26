import AppIntents

// The intents behind the Control Center and Lock Screen controls. Each opens the app, where `perform()` runs in the
// app's own process and leaves the request in `InboundChatMailbox`. They are compiled into the app and the controls
// extension, so the system finds them in both. "New chat" and "Start voice" also show in Shortcuts and as App Shortcuts, so
// they can go on the Action Button.

struct NewChatControlIntent: AppIntent {
    static let title: LocalizedStringResource = "New chat"
    static let description = IntentDescription("Open AnyRouter on a new chat.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        InboundChatMailbox.shared.post(InboundChat())
        return .result()
    }
}

/// A new chat that starts dictating into the composer.
struct VoiceControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Start voice"
    static let description = IntentDescription("Open AnyRouter on a new chat and start dictating.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        InboundChatMailbox.shared.post(InboundChat(startsVoice: true))
        return .result()
    }
}

/// Opens "Fix my English" with a Paste button. A control cannot hand over the clipboard, and reading it in the app
/// would raise the system's paste prompt, so the person taps the system Paste button instead.
struct PasteAndFixControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Paste and fix"
    static let description = IntentDescription("Paste a text and have AnyRouter fix its English.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        InboundChatMailbox.shared.post(InboundChat(presetID: InboundPreset.fixEnglish, asksForText: true))
        return .result()
    }
}
