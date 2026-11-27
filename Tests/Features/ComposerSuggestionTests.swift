import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// What shows above the composer, in what order, and what a chip does. One row replaces the starter cards, the
/// clipboard row and the paste offer, so the rules that kept them from piling up live here.
@MainActor
struct ComposerSuggestionTests {
    private func preset(_ id: String, offered: Bool = false, options: Bool = false) -> PromptPreset {
        PromptPreset(
            id: id, title: id.capitalized, prompt: "\(id):\n", category: .write, symbol: "sparkles",
            options: options ? [PresetOption(id: "tone", title: "Tone", choices: [.init(id: "plain", title: "Plain", wording: "plain")])] : nil,
            offerOnPaste: offered)
    }

    private let six = ["a", "b", "c", "d", "e", "f"]

    private func state(
        messages: Bool = false, empty: Bool = true, clipboard: Bool = false, pasted: Bool = false,
        dictating: Bool = false, mentions: Bool = false
    ) -> ComposerSuggestionState {
        ComposerSuggestionState(chatHasMessages: messages, inputIsEmpty: empty, clipboardOffered: clipboard,
                                pasteOffered: pasted, isDictating: dictating, mentionPanelOpen: mentions)
    }

    private func show(_ state: ComposerSuggestionState, text: [String] = ["fix", "sum"], starters: [String] = ["a", "b", "c"]) -> ComposerSuggestions? {
        ComposerSuggestionLogic.visible(state, textPresets: text.map { preset($0) }, starters: starters.map { preset($0) })
    }

    private func ids(_ suggestions: ComposerSuggestions?) -> [String] { suggestions?.items.map(\.id) ?? [] }

    // MARK: - Visibility

    @Test func anEmptyChatWithAnEmptyComposerOffersStarters() {
        let shown = show(state())
        #expect(shown?.mode == .starters)
        #expect(ids(shown) == ["preset.a", "preset.b", "preset.c", "more"])
    }

    @Test func atMostFourPresetsShowAndTheRestAreInMore() {
        let shown = show(state(), starters: six)
        #expect(ids(shown) == ["preset.a", "preset.b", "preset.c", "preset.d", "more"])
    }

    @Test func startersLeaveOnceTheChatHasMessages() {
        #expect(show(state(messages: true)) == nil)
    }

    @Test func typingHidesEverythingAndAPasteIsTheOnlyTextThatKeepsItShowing() {
        #expect(show(state(empty: false)) == nil)
        #expect(show(state(empty: false, clipboard: true)) == nil, "the clipboard is offered to an empty composer only")
        #expect(show(state(empty: false, pasted: true))?.mode == .pasted)
    }

    @Test func dictatingAndTheAtListHideEveryMode() {
        for flags in [state(dictating: true), state(mentions: true),
                      state(clipboard: true, dictating: true), state(clipboard: true, mentions: true),
                      state(empty: false, pasted: true, dictating: true), state(empty: false, pasted: true, mentions: true)] {
            #expect(show(flags) == nil)
        }
    }

    // MARK: - Order

    @Test func theSystemPasteButtonComesFirstWhenTheClipboardChanged() {
        let shown = show(state(clipboard: true))
        #expect(shown?.mode == .clipboard)
        #expect(ids(shown) == ["paste", "preset.fix", "preset.sum", "more"], "text presets, not the starters")
    }

    @Test func theClipboardIsOfferedInAChatThatAlreadyHasMessages() {
        #expect(show(state(messages: true, clipboard: true))?.mode == .clipboard)
    }

    @Test func aFreshPasteShowsTextPresetsWithoutAPasteButton() {
        let shown = show(state(empty: false, pasted: true))
        #expect(ids(shown) == ["preset.fix", "preset.sum", "more"])
    }

    @Test func aPasteInTheFieldWinsOverTheClipboardOffer() {
        #expect(show(state(empty: false, clipboard: true, pasted: true))?.mode == .pasted)
    }

    @Test func theClipboardRowCapsPresetsAtFourToo() {
        let shown = show(state(clipboard: true), text: six)
        #expect(ids(shown) == ["paste", "preset.a", "preset.b", "preset.c", "preset.d", "more"])
    }

    @Test func noPresetsMeansNoMoreMenuAndNoEmptyRow() {
        #expect(ids(show(state(clipboard: true), text: [])) == ["paste"], "the Paste button still works without presets")
        #expect(show(state(), starters: []) == nil)
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
        return PresetStore(fileURL: url, builtIns: [
            preset("fix", offered: true), preset("reply", offered: true, options: true), preset("plan"), preset("idea"), preset("quiz"), preset("draft"),
        ])
    }

    private func suggestions(_ vm: ChatViewModel, _ presets: PresetStore, clipboard: Bool = false) -> ComposerSuggestions? {
        vm.suggestions(presets: presets, clipboardOffered: clipboard, isDictating: false, mentionPanelOpen: false)
    }

    @Test func aNewChatShowsStartersWithTheHelpersFirstAndTheyGoAfterTheFirstMessage() async throws {
        let vm = try await chat()
        let presets = store()
        let first = suggestions(vm, presets)
        let helper = try #require(presets.all.first { $0.id == "reply" })
        #expect(first?.mode == .starters)
        #expect(first?.items.count == ComposerSuggestionLogic.maxPresets + 1)
        #expect(first?.items.first == .preset(helper), "presets with pickers lead")
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
