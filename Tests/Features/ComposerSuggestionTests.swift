import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// What shows above the composer, in what order, and what a chip does. One row holds the starters, the clipboard's
/// actions and the paste offer, so the rules that keep them from piling up live here. The cards follow what is on the
/// clipboard without reading it, and only offer what the model can do.
@MainActor
struct ComposerSuggestionTests {
    private func preset(_ id: String, offered: Bool = false, options: Bool = false) -> PromptPreset {
        PromptPreset(
            id: id, title: id.capitalized, prompt: "\(id):\n", category: .write, symbol: "sparkles",
            options: options ? [PresetOption(id: "tone", title: "Tone", choices: [.init(id: "plain", title: "Plain", wording: "plain")])] : nil,
            offerOnPaste: offered)
    }

    private let six = ["a", "b", "c", "d", "e", "f"]

    /// Every preset the rules name, as the store would hand them over.
    private let catalog = [
        "fix-english", "explain-text", "translate", "summarize", "reply-to-this", "summarize-link", "about-link", "describe-image",
        "read-photo", "what-time", "plan-day", "write-message", "ask-photo", "explain-simply", "what-can-you-do",
    ]

    private func state(
        messages: Bool = false, empty: Bool = true, clipboard: ClipboardKind? = nil, content: ClipboardKind? = nil,
        pasted: Bool = false, dictating: Bool = false, mentions: Bool = false, tools: Bool = true, vision: Bool = true
    ) -> ComposerSuggestionState {
        ComposerSuggestionState(chatHasMessages: messages, inputIsEmpty: empty, clipboardKind: clipboard, clipboardContent: content,
                                pasteOffered: pasted, isDictating: dictating, mentionPanelOpen: mentions,
                                supportsTools: tools, supportsVision: vision)
    }

    private func show(
        _ state: ComposerSuggestionState, presets: [String]? = nil, custom: Set<String> = [], text: [String] = ["fix", "sum"]
    ) -> ComposerSuggestions? {
        ComposerSuggestionLogic.visible(
            state, presets: (presets ?? catalog).map { preset($0) }, customIDs: custom, textPresets: text.map { preset($0) })
    }

    private func ids(_ suggestions: ComposerSuggestions?) -> [String] { suggestions?.items.map(\.id) ?? [] }

    // MARK: - An empty chat

    @Test func nothingCopiedOffersStartersThatWorkRightAway() {
        let shown = show(state())
        #expect(shown?.mode == .starters && shown?.cards == true)
        #expect(ids(shown) == ["preset.what-time", "preset.plan-day", "preset.write-message", "preset.ask-photo", "more"])
    }

    /// The clock needs a tool and a photo question a model that sees photos, so neither is offered without them.
    @Test func theStartersLeaveOutWhatTheModelCannotDo() {
        #expect(ids(show(state(tools: false, vision: false))) ==
            ["preset.plan-day", "preset.write-message", "preset.explain-simply", "preset.what-can-you-do", "more"])
        #expect(ids(show(state(vision: false))) ==
            ["preset.what-time", "preset.plan-day", "preset.write-message", "preset.explain-simply", "more"])
        #expect(ComposerSuggestionLogic.starterPresetIDs(tools: true, vision: true) ==
            ["what-time", "plan-day", "write-message", "ask-photo", "explain-simply", "what-can-you-do"])
    }

    @Test func yourOwnPresetsLeadTheStarters() {
        let shown = show(state(), presets: ["mine"] + catalog, custom: ["mine"])
        #expect(ids(shown) == ["preset.mine", "preset.what-time", "preset.plan-day", "preset.write-message", "more"])
    }

    @Test func copiedTextTurnsTheCardsIntoActionsOnItAndMoreHoldsTheFifth() {
        let shown = show(state(content: .text))
        #expect(shown?.mode == .clipboard && shown?.cards == true)
        #expect(ids(shown) == ["preset.fix-english", "preset.explain-text", "preset.translate", "preset.summarize", "more"])
    }

    /// On an empty chat the cards say what they do with the copy, so a fresh copy adds no chip of its own.
    @Test func aFreshCopyOnAnEmptyChatIsOnlyCards() {
        let shown = show(state(clipboard: .text, content: .text))
        #expect(ids(shown) == ["preset.fix-english", "preset.explain-text", "preset.translate", "preset.summarize", "more"])
        #expect(ids(show(state(clipboard: .image))) == ["preset.describe-image", "preset.read-photo", "more"],
                "the offer alone picks the cards too")
    }

    /// Opening a page needs tools; without them a link has nothing to act on, so the general starters show.
    @Test func aLinkIsOfferedOnlyToAModelThatCanOpenIt() {
        #expect(ids(show(state(content: .link))) == ["preset.summarize-link", "preset.about-link", "more"])
        let noTools = show(state(clipboard: .link, content: .link, tools: false))
        #expect(noTools?.mode == .starters)
        #expect(ids(noTools) == ["preset.plan-day", "preset.write-message", "preset.ask-photo", "preset.explain-simply", "more"])
    }

    /// Reading the text in a picture runs on the device, so it is offered for any model.
    @Test func aPictureIsDescribedOnlyByAModelThatSeesIt() {
        #expect(ids(show(state(content: .image))) == ["preset.describe-image", "preset.read-photo", "more"])
        #expect(ids(show(state(content: .image, vision: false))) == ["preset.read-photo", "more"])
    }

    /// More lists every preset; only the copy's own actions read it, so "Answer offline" from More never sends the copy.
    @Test func onlyTheCopysOwnActionsReadIt() {
        #expect(ComposerSuggestionLogic.actsOnClipboard(preset("summarize"), kind: .text, tools: false, vision: false))
        #expect(!ComposerSuggestionLogic.actsOnClipboard(preset("go-offline"), kind: .text, tools: true, vision: true))
        #expect(!ComposerSuggestionLogic.actsOnClipboard(preset("summarize-link"), kind: .link, tools: false, vision: true))
        #expect(ComposerSuggestionLogic.actsOnClipboard(preset("summarize-link"), kind: .link, tools: true, vision: false))
    }

    @Test func aHiddenPresetIsLeftOut() {
        let shown = show(state(content: .text), presets: catalog.filter { $0 != "explain-text" })
        #expect(ids(shown) == ["preset.fix-english", "preset.translate", "preset.summarize", "preset.reply-to-this", "more"])
    }

    // MARK: - A chat with messages

    @Test func aChatWithMessagesShowsOnlyAFreshCopyAsChips() {
        #expect(show(state(messages: true)) == nil)
        #expect(show(state(messages: true, content: .text)) == nil, "what has sat on the clipboard is not offered mid-chat")
        let shown = show(state(messages: true, clipboard: .text, content: .text))
        #expect(shown?.mode == .clipboard && shown?.cards == false)
        #expect(ids(shown) == ["clipboard", "preset.fix-english", "preset.explain-text", "preset.translate", "preset.summarize", "more"])
    }

    // MARK: - Typing, pasting, dictating

    @Test func typingHidesEverythingAndAPasteIsTheOnlyTextThatKeepsItShowing() {
        #expect(show(state(empty: false)) == nil)
        #expect(show(state(empty: false, clipboard: .text, content: .text)) == nil, "the clipboard is offered to an empty composer only")
        let pasted = show(state(empty: false, pasted: true))
        #expect(pasted?.mode == .pasted && pasted?.cards == false)
    }

    @Test func dictatingAndTheAtListHideEveryMode() {
        for flags in [state(dictating: true), state(mentions: true),
                      state(clipboard: .text, dictating: true), state(content: .text, mentions: true),
                      state(empty: false, pasted: true, dictating: true), state(empty: false, pasted: true, mentions: true)] {
            #expect(show(flags) == nil)
        }
    }

    @Test func aFreshPasteShowsTextPresetsWithoutAPasteButton() {
        #expect(ids(show(state(empty: false, pasted: true))) == ["preset.fix", "preset.sum", "more"])
        #expect(show(state(empty: false, clipboard: .text, pasted: true))?.mode == .pasted, "a paste wins over the clipboard offer")
        #expect(ids(show(state(empty: false, pasted: true), text: six)) == ["preset.a", "preset.b", "preset.c", "preset.d", "more"])
    }

    @Test func noPresetsMeansNoMoreMenuAndNoEmptyRow() {
        #expect(ids(show(state(messages: true, clipboard: .text), presets: [])) == ["clipboard"], "the copy's chip still works without presets")
        #expect(show(state(clipboard: .text), presets: []) == nil)
        #expect(show(state(), presets: []) == nil)
        #expect(show(state(empty: false, pasted: true), text: []) == nil)
    }

    // MARK: - From the chat

    private func chat() async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["ok"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models)
    }

    private func store() -> PresetStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("suggestions-\(UUID().uuidString).json")
        return PresetStore(fileURL: url, builtIns: [preset("fix", offered: true), preset("reply", offered: true, options: true)]
            + catalog.map { preset($0) })
    }

    private func suggestions(_ vm: ChatViewModel, _ presets: PresetStore, clipboard: ClipboardKind? = nil) -> ComposerSuggestions? {
        vm.suggestions(presets: presets, clipboardKind: clipboard, clipboardContent: clipboard, isDictating: false, mentionPanelOpen: false)
    }

    @Test func aNewChatShowsStartersForItsModelAndTheyGoAfterTheFirstMessage() async throws {
        let vm = try await chat()
        let presets = store()
        let first = suggestions(vm, presets)
        let expected = ComposerSuggestionLogic.starterPresetIDs(tools: vm.supportsTools, vision: vm.model?.supportsVision == true)
        #expect(first?.mode == .starters)
        #expect(first?.items.dropLast().map(\.id) == expected.prefix(ComposerSuggestionLogic.maxPresets).map { "preset.\($0)" })
        presets.add(title: "Mine", prompt: "Mine", category: .write)
        #expect(suggestions(vm, presets)?.items.first?.id == "preset.\(presets.custom[0].id)", "your own preset leads")
        vm.input = "hello"
        await vm.send()?.value
        #expect(suggestions(vm, presets) == nil)
    }

    @Test func typingHidesTheRowAndAPasteBringsTheTextPresetsBack() async throws {
        let vm = try await chat()
        let presets = store()
        vm.input = "hi"
        vm.inputChanged(from: "", to: "hi")
        #expect(suggestions(vm, presets) == nil)
        let pasted = "hi This sentence has a few mistakes in it, please fix them."
        vm.input = pasted
        vm.inputChanged(from: "hi", to: pasted)
        let shown = suggestions(vm, presets)
        #expect(shown?.mode == .pasted)
        #expect(ids(shown) == ["preset.fix", "preset.reply", "more"])
    }

    // MARK: - Taps

    @Test func aStarterTapFillsTheComposerAndNeverReadsTheClipboard() async throws {
        let vm = try await chat()
        var reads = 0
        let task = vm.choose(preset("plan"), mode: .starters, clipboardText: { reads += 1; return "secret" })
        #expect(task == nil)
        #expect(vm.input == "plan:\n")
        #expect(reads == 0, "the text is only read for a clipboard tap")
    }

    @Test func aTapAfterAPasteWrapsThePastedText() async throws {
        let vm = try await chat()
        let paragraph = "This sentence has a few mistakes in it, please fix them."
        vm.input = paragraph
        vm.inputChanged(from: "", to: paragraph)
        vm.choose(preset("fix", offered: true), mode: .pasted, clipboardText: { Issue.record("must not read the clipboard"); return "" })
        #expect(vm.input == "fix:\n" + paragraph)
        #expect(!vm.pasteOffered)
    }

    @Test func aClipboardTapReadsTheClipboardOnceAndSends() async throws {
        let vm = try await chat()
        var reads = 0
        let task = vm.choose(preset("fix", offered: true), mode: .clipboard, clipboardText: { reads += 1; return "Teh quick fox" })
        await task?.value
        #expect(reads == 1)
        #expect(vm.messages.first?.content == "fix:\nTeh quick fox")
    }

    @Test func aPresetWithPickersOpensItsChoicesInEveryMode() async throws {
        for mode in [ComposerSuggestionMode.starters, .clipboard, .pasted] {
            let vm = try await chat()
            vm.input = "A long enough message to reply to, honestly."
            vm.choose(preset("reply", offered: true, options: true), mode: mode, clipboardText: { "A long enough message to reply to, honestly." })
            #expect(vm.presetNeedingChoices?.id == "reply")
        }
    }
}
