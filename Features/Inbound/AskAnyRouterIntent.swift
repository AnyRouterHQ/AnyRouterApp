import AppIntents

/// A preset Shortcuts can list and pass to an intent.
struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Preset")
    static let defaultQuery = PresetEntityQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct PresetEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PresetEntity] {
        await Self.visible().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        await Self.visible()
    }

    /// The presets the user sees in the app: their own first, then the built-ins they have not hidden.
    static func visible() async -> [PresetEntity] {
        await MainActor.run { PresetStore().all.map { PresetEntity(id: $0.id, title: $0.title) } }
    }
}

/// Opens the app on a fresh chat. The text goes into the composer, the preset is applied, and "Send now" sends it.
struct AskAnyRouterIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask AnyRouter"
    static let description = IntentDescription("Start a new chat with your text and an optional preset.")
    static let openAppWhenRun = true

    @Parameter(title: "Text")
    var text: String?

    @Parameter(title: "Preset")
    var preset: PresetEntity?

    @Parameter(title: "Send now", default: false)
    var sendNow: Bool

    init() {}

    init(text: String?, preset: PresetEntity?, sendNow: Bool = false) {
        self.text = text
        self.preset = preset
        self.sendNow = sendNow
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        InboundChatMailbox.shared.post(InboundChat(text: text, presetID: preset?.id, sendNow: sendNow))
        return .result()
    }
}

/// Fixes the grammar of the text a Shortcut passes in (for example the clipboard) and sends it right away.
struct FixMyEnglishIntent: AppIntent {
    static let title: LocalizedStringResource = "Fix my English"
    static let description = IntentDescription("Correct the grammar, spelling and wording of a text.")
    static let openAppWhenRun = true

    @Parameter(title: "Text", requestValueDialog: IntentDialog("Which text should I fix?"))
    var text: String

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        InboundChatMailbox.shared.post(InboundChat(text: text, presetID: InboundPreset.fixEnglish, sendNow: true))
        return .result()
    }
}

/// The phrases Siri and Spotlight know without any setup. Free text cannot sit in a phrase, so Siri asks for it.
struct AnyRouterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAnyRouterIntent(),
            phrases: ["Ask \(.applicationName)"],
            shortTitle: "Ask AnyRouter",
            systemImageName: "bubble.left.and.text.bubble.right")
        AppShortcut(
            intent: FixMyEnglishIntent(),
            phrases: ["Fix my English with \(.applicationName)"],
            shortTitle: "Fix my English",
            systemImageName: "text.badge.checkmark")
        AppShortcut(
            intent: NewChatControlIntent(),
            phrases: ["New chat in \(.applicationName)"],
            shortTitle: "New chat",
            systemImageName: "square.and.pencil")
        AppShortcut(
            intent: VoiceControlIntent(),
            phrases: ["Start voice with \(.applicationName)"],
            shortTitle: "Start voice",
            systemImageName: "waveform")
    }
}
