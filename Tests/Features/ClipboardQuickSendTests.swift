import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// The clipboard offer: what kind of copy it is (known without reading it), which quick actions it offers, and the
/// message a quick action sends. The point is one tap from a copy to a sent message, with a badge that says so.
@MainActor
struct ClipboardQuickSendTests {
    private final class Board: PasteboardProbe, @unchecked Sendable {
        var changeCount = 1
        var hasStrings = true
        var hasURLs = false
        var hasImages = false
    }

    private func bundled() -> PresetStore {
        PresetStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("quick-\(UUID().uuidString).json"))
    }

    private func preset(_ id: String) throws -> PromptPreset {
        try #require(bundled().all.first { $0.id == id })
    }

    // MARK: Kind

    @Test func anImageWinsOverALinkAndALinkOverText() {
        #expect(ClipboardLaunchLogic.kind(hasStrings: true, hasURLs: true, hasImages: true) == .image)
        #expect(ClipboardLaunchLogic.kind(hasStrings: true, hasURLs: true, hasImages: false) == .link)
        #expect(ClipboardLaunchLogic.kind(hasStrings: true, hasURLs: false, hasImages: false) == .text)
        #expect(ClipboardLaunchLogic.kind(hasStrings: false, hasURLs: false, hasImages: false) == nil)
    }

    @Test func eachKindHasItsOwnSymbolAndWords() {
        #expect([ClipboardKind.text, .link, .image].map(\.symbol) == ["doc.on.clipboard", "link", "photo"])
        #expect([ClipboardKind.text, .link, .image].map(\.title) == ["Copied text", "Copied link", "Copied image"])
    }

    @Test func theLauncherOffersTheKindOncePerCopyAndADismissHoldsUntilTheNextCopy() {
        let board = Board()
        board.hasURLs = true
        let launcher = ClipboardLauncher(probe: board, defaults: testDefaults())
        launcher.check(composerEmpty: true)
        #expect(launcher.offeredKind == .link)
        launcher.dismiss()
        launcher.check(composerEmpty: true)
        #expect(launcher.offeredKind == nil, "a dismissed copy stays dismissed")
        board.changeCount += 1
        board.hasURLs = false
        board.hasImages = true
        launcher.check(composerEmpty: true)
        #expect(launcher.offeredKind == .image, "the next copy is offered, by its own kind")
    }

    // MARK: Chips

    @Test func everyQuickActionAndStarterIsABundledPreset() {
        let ids = Set(bundled().all.map(\.id))
        var named = ComposerSuggestionLogic.starterPresetIDs(tools: true, vision: true)
        for kind in [ClipboardKind.text, .link, .image] {
            named += ComposerSuggestionLogic.clipboardPresetIDs(kind, tools: true, vision: true)
        }
        for id in named {
            #expect(ids.contains(id), "\(id) is not in presets.json")
        }
    }

    @Test func theRowLeadsWithTheCopyThenItsQuickActionsThenMore() throws {
        let store = bundled()
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        let vm = ChatViewModel(thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()),
                               models: ModelStore(registry: registry, defaults: testDefaults()))
        // No model is chosen, so the row offers what works without tools or photos.
        let text = vm.suggestions(presets: store, clipboardKind: .text, clipboardContent: .text, isDictating: false, mentionPanelOpen: false)
        #expect(text?.mode == .clipboard)
        #expect(text?.items.map(\.id) == ["clipboard", "preset.fix-english", "preset.explain-text", "preset.translate", "preset.summarize", "more"])
        let link = vm.suggestions(presets: store, clipboardKind: .link, clipboardContent: .link, isDictating: false, mentionPanelOpen: false)
        #expect(link?.mode == .starters, "a model without tools cannot open the link")
        let image = vm.suggestions(presets: store, clipboardKind: .image, clipboardContent: .image, isDictating: false, mentionPanelOpen: false)
        #expect(image?.items.map(\.id) == ["clipboard", "preset.read-photo", "more"])
    }

    // MARK: Prompt

    @Test func aTextActionIsThePromptThenTheCopy() throws {
        let fix = try preset("fix-english")
        let sent = ClipboardQuickSend.prompt(fix, text: "  Teh quick fox  ", deviceLanguage: "en")
        #expect(sent == fix.prompt + "Teh quick fox")
        #expect(ClipboardQuickSend.prompt(fix, text: " \n ", deviceLanguage: "en") == nil, "nothing to send")
    }

    @Test func translateGoesIntoTheDeviceLanguageOrIntoEnglishWhenTheTextIsAlreadyInIt() throws {
        let translate = try preset("translate")
        let english = "The meeting moved to Friday afternoon, please bring the revised budget with you."
        let vietnamese = "Cuộc họp đã được dời sang chiều thứ Sáu, vui lòng mang theo ngân sách đã sửa đổi."
        #expect(ClipboardQuickSend.prompt(translate, text: english, deviceLanguage: "vi")?.contains("into Vietnamese") == true)
        #expect(ClipboardQuickSend.prompt(translate, text: vietnamese, deviceLanguage: "vi")?.contains("into English") == true)
        #expect(ClipboardQuickSend.prompt(translate, text: vietnamese, deviceLanguage: "en")?.contains("into English") == true)
    }

    @Test func aLinkActionCarriesTheLink() throws {
        let points = try preset("key-points")
        let sent = ClipboardQuickSend.prompt(points, text: "https://example.com/post", deviceLanguage: "en")
        #expect(sent?.hasSuffix("https://example.com/post") == true)
    }

    // MARK: Send

    private func chat() async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["ok"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models)
    }

    @Test func aQuickActionSendsAtOnceWithTheClipboardBadge() async throws {
        let vm = try await chat()
        let task = vm.quickSend(try preset("summarize"), text: "A long note about the budget.", deviceLanguage: "en")
        await task?.value
        let user = try #require(vm.messages.first { $0.role == .user })
        #expect(user.fromClipboard)
        #expect(user.content.hasSuffix("A long note about the budget."))
        vm.input = "and a normal follow-up"
        await vm.send()?.value
        let followUp = try #require(vm.messages.last { $0.role == .user })
        #expect(!followUp.fromClipboard, "only the quick action carries the badge")
    }

    @Test func aQuickActionThatSendsNothingLeavesNoBadgeForTheNextMessage() async throws {
        let vm = try await chat()
        let task = vm.quickSend(try preset("summarize"), text: "   ", deviceLanguage: "en")
        #expect(task == nil)
        vm.input = "typed by hand"
        await vm.send()?.value
        let user = try #require(vm.messages.first { $0.role == .user })
        #expect(!user.fromClipboard)
    }
}
