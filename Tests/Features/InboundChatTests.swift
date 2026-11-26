import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
@Suite(.serialized)
struct InboundChatTests {
    private func preset(_ prompt: String, id: String = "p") -> PromptPreset {
        PromptPreset(id: id, title: "T", prompt: prompt, category: .write, symbol: "sparkles")
    }

    // MARK: Composer text

    @Test func textAloneGoesInTrimmed() {
        #expect(InboundChatLogic.composerText(preset: nil, text: "  hello \n") == "hello")
        #expect(InboundChatLogic.composerText(preset: nil, text: nil).isEmpty)
    }

    @Test func aPresetAloneFillsItsPrompt() {
        #expect(InboundChatLogic.composerText(preset: preset("Do it"), text: nil) == "Do it")
        #expect(InboundChatLogic.composerText(preset: preset("Do it"), text: "   ") == "Do it")
    }

    @Test func textFollowsAPromptThatEndsInALineBreakDirectly() {
        #expect(InboundChatLogic.composerText(preset: preset("Email:\n"), text: "Hi Sam") == "Email:\nHi Sam")
    }

    @Test func textFollowsOtherPromptsAfterABlankLine() {
        #expect(InboundChatLogic.composerText(preset: preset("Summarize this."), text: "Long text")
                == "Summarize this.\n\nLong text")
    }

    // MARK: Mailbox and shell

    @Test func theMailboxHandsOverEachRequestOnce() {
        let mailbox = InboundChatMailbox()
        let request = InboundChat(text: "hi")
        mailbox.post(request)
        #expect(mailbox.pending == request)
        #expect(mailbox.take() == request)
        #expect(mailbox.take() == nil)
        #expect(mailbox.pending == nil)
    }

    @Test func aRequestOpensAFreshChatOverEverything() {
        let shell = ShellModel(selectedThreadID: UUID())
        shell.isSidebarOpen = true
        shell.isSettingsPresented = true
        shell.isSearchPresented = true
        shell.isModelPickerPresented = true
        let request = InboundChat(text: "hi", presetID: "x", sendNow: true)

        shell.start(request)
        #expect(shell.selectedThreadID == nil)
        #expect(!shell.isSidebarOpen && !shell.isSettingsPresented && !shell.isSearchPresented && !shell.isModelPickerPresented)
        #expect(shell.inbound == request)
        #expect(shell.takeInbound() == request)
        #expect(shell.inbound == nil)
        #expect(shell.takeInbound() == nil)
    }

    // MARK: Chat

    private func chat(chunks: [String] = ["ok"]) async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: chunks))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: nil, context: context, registry: registry,
                             settings: AppSettings(defaults: testDefaults()), models: models)
    }

    @Test func aRequestFillsTheComposerAndFocusesIt() async throws {
        let vm = try await chat()
        let task = vm.start(InboundChat(text: "Hi Sam", presetID: "p"), preset: preset("Email:\n"))
        #expect(task == nil)
        #expect(vm.input == "Email:\nHi Sam")
        #expect(vm.focusTick == 1)
        #expect(vm.messages.isEmpty)
    }

    @Test func aSendNowRequestSendsIt() async throws {
        let vm = try await chat()
        await vm.start(InboundChat(text: "Fix this", sendNow: true), preset: nil)?.value
        #expect(vm.messages.map(\.role) == [.user, .assistant])
        #expect(vm.messages.first?.content == "Fix this")
        #expect(vm.input.isEmpty)
    }

    @Test func aSendNowRequestWithNothingToSendDoesNotSend() async throws {
        let vm = try await chat()
        #expect(vm.start(InboundChat(sendNow: true), preset: nil) == nil)
        #expect(vm.messages.isEmpty)
    }

    // MARK: Presets

    @Test func presetLookupFindsHiddenBuiltInsAndCustomOnes() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("presets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PresetStore(fileURL: url, builtIns: [preset("A", id: "a"), preset("B", id: "b")])
        let mine = store.add(title: "Mine", prompt: "M", category: .write)
        store.setBuiltInHidden("a", hidden: true)

        #expect(store.preset(id: "a")?.prompt == "A")
        #expect(store.preset(id: mine.id)?.prompt == "M")
        #expect(store.preset(id: "missing") == nil)
    }

    @Test func theShippedPresetsIncludeFixMyEnglish() throws {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        let fix = try #require(items.first { $0.id == InboundPreset.fixEnglish })
        #expect(fix.prompt.hasSuffix("\n"), "the pasted text goes right after the prompt")
    }

    // MARK: Intents

    @Test func theAskIntentLeavesAFreshChatRequest() async throws {
        let mailbox = InboundChatMailbox.shared
        _ = mailbox.take()
        let entity = PresetEntity(id: "fix-english", title: "Fix my English")
        _ = try await AskAnyRouterIntent(text: "hi", preset: entity, sendNow: true).perform()
        let request = try #require(mailbox.take())
        #expect(request.text == "hi")
        #expect(request.presetID == "fix-english")
        #expect(request.sendNow)

        _ = try await AskAnyRouterIntent().perform()
        let bare = try #require(mailbox.take())
        #expect(bare.text == nil && bare.presetID == nil && !bare.sendNow)
    }

    @Test func fixMyEnglishSendsTheTextItIsGiven() async throws {
        let mailbox = InboundChatMailbox.shared
        _ = mailbox.take()
        _ = try await FixMyEnglishIntent(text: "me and him goes").perform()
        let request = try #require(mailbox.take())
        #expect(request.text == "me and him goes")
        #expect(request.presetID == InboundPreset.fixEnglish)
        #expect(request.sendNow)
    }

    // MARK: Controls

    @Test func theControlsOpenAFreshChatAndPasteAndFixAsksForTheText() async throws {
        let mailbox = InboundChatMailbox.shared
        _ = mailbox.take()

        _ = try await NewChatControlIntent().perform()
        let fresh = try #require(mailbox.take())
        #expect(fresh.text == nil && fresh.presetID == nil && !fresh.sendNow && !fresh.asksForText)

        _ = try await VoiceControlIntent().perform()
        let voice = try #require(mailbox.take())
        #expect(voice.text == nil && voice.presetID == nil && !voice.asksForText)

        _ = try await PasteAndFixControlIntent().perform()
        let fix = try #require(mailbox.take())
        #expect(fix.presetID == InboundPreset.fixEnglish)
        #expect(fix.asksForText && !fix.sendNow, "the clipboard is not read: the person pastes with the system button")
    }

    @Test func aRequestThatAsksForTextOpensThePresetSheetWithoutFillingTheComposer() async throws {
        let vm = try await chat()
        let fix = preset("Fix:\n", id: "fix")
        let task = vm.start(InboundChat(presetID: "fix", asksForText: true), preset: fix)
        #expect(task == nil)
        #expect(vm.presetNeedingChoices?.id == "fix")
        #expect(vm.input.isEmpty)
        #expect(vm.messages.isEmpty)

        vm.presetNeedingChoices = nil
        _ = vm.start(InboundChat(text: "me and him goes", presetID: "fix", asksForText: true), preset: fix)
        #expect(vm.input == "me and him goes", "the text is the sheet's message")
    }

    @Test func aRequestThatAsksForTextWithoutItsPresetJustFillsTheComposer() async throws {
        let vm = try await chat()
        _ = vm.start(InboundChat(text: "hello", presetID: "gone", asksForText: true), preset: nil)
        #expect(vm.presetNeedingChoices == nil)
        #expect(vm.input == "hello")
    }

    @Test func shortcutsListThePresetsTheUserSees() async throws {
        let all = await PresetEntityQuery.visible()
        #expect(all.contains { $0.id == InboundPreset.fixEnglish })
        let suggested = try await PresetEntityQuery().suggestedEntities()
        #expect(suggested.map(\.id) == all.map(\.id))
        let picked = try await PresetEntityQuery().entities(for: [InboundPreset.fixEnglish, "missing"])
        #expect(picked.map(\.id) == [InboundPreset.fixEnglish])
        #expect(String(localized: PresetEntity(id: "x", title: "Title").displayRepresentation.title) == "Title")
    }

    @Test func twoAppShortcutsAreRegistered() {
        #expect(AnyRouterShortcuts.appShortcuts.count == 2)
    }
}
