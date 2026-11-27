import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// The phone use cases that sit among the presets: what they start from, and what "Answer offline" decides.
@MainActor
struct UseCaseTests {
    // MARK: Presets

    private func bundled() throws -> [PromptPreset] {
        try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
    }

    @Test func theSixPhoneUseCasesAreBuiltInAndGroupedOnTheDevice() throws {
        let useCases = try bundled().filter(\.onDevice)
        #expect(useCases.map(\.id) == ["reply-to-this", "fix-english", "read-photo", "ask-clipboard", "summarize-link", "go-offline"])
        #expect(useCases.compactMap(\.action) == [.readPhoto, .askClipboard, .summarizeLink, .goOffline])
        #expect(useCases.filter { $0.action == nil }.allSatisfy { !$0.prompt.isEmpty }, "reply and fix English are real prompts")
    }

    @Test func useCasesLeadTheStartersAfterYourOwnPresets() throws {
        let items = try bundled()
        let row = PresetLogic.featured(items, customIDs: [], category: nil, seed: 7, limit: 4)
        #expect(row.map(\.id) == ["reply-to-this", "fix-english", "read-photo", "ask-clipboard"])
        let mine = PromptPreset(id: "mine", title: "Mine", prompt: "x", category: .write, symbol: "sparkles")
        #expect(PresetLogic.featured([mine] + items, customIDs: ["mine"], category: nil, seed: 7, limit: 2).map(\.id) == ["mine", "reply-to-this"])
    }

    @Test func aPresetFileWithoutTheNewKeysStillDecodesAndTheKeysRoundTrip() throws {
        let old = Data(##"{"id":"a","title":"A","prompt":"P","category":"write","symbol":"sparkles"}"##.utf8)
        let decoded = try JSONDecoder().decode(PromptPreset.self, from: old)
        #expect(decoded.action == nil && !decoded.onDevice)
        let use = PromptPreset(id: "u", title: "U", prompt: "", category: .explore, symbol: "link", action: .summarizeLink, onDevice: true)
        let back = try JSONDecoder().decode(PromptPreset.self, from: JSONEncoder().encode(use))
        #expect(back == use)
    }

    @Test func everyActionSaysWhatItDoesInTheList() {
        for action in PresetAction.allCases {
            let preset = PromptPreset(id: "u", title: "U", prompt: "", category: .explore, symbol: "link", action: action)
            #expect(PresetOptionsLogic.summary(preset) == action.summary)
            #expect(!action.summary.isEmpty)
        }
    }

    // MARK: Clipboard texts

    @Test func askingAboutTheClipboardKeepsTheTextAndEndsOnTheQuestion() {
        #expect(UseCaseLogic.clipboardQuestion("  \n ") == nil)
        #expect(UseCaseLogic.clipboardQuestion(" Meeting moved to 5pm \n") == "About this text:\nMeeting moved to 5pm\n\nMy question: ")
    }

    @Test func theFirstWebLinkIsFoundAndOtherSchemesAreNot() {
        #expect(UseCaseLogic.firstLink(in: "see https://example.com/a?x=1 and https://other.dev")?.absoluteString == "https://example.com/a?x=1")
        #expect(UseCaseLogic.firstLink(in: "mail me at a@b.com") == nil, "mailto is not a page")
        #expect(UseCaseLogic.firstLink(in: "ftp://files.example.com/x") == nil)
        #expect(UseCaseLogic.firstLink(in: "no link here") == nil)
    }

    @Test func aCopiedLinkMakesAReadyRequestAndNoLinkAsksForOne() {
        let ready = UseCaseLogic.linkRequest("https://example.com/post")
        #expect(ready.isReady)
        #expect(ready.text.hasSuffix("\nhttps://example.com/post"))
        let waiting = UseCaseLogic.linkRequest("just words")
        #expect(!waiting.isReady)
        #expect(waiting.text == "Summarize this page:\n")
        #expect(UseCaseLogic.cannotOpenLinks("Qwen").hasPrefix("Qwen cannot open links"))
    }

    // MARK: Answer offline

    private func entry(_ id: String, mb: Int64, fit: ModelFit, reason: String? = nil, deprecated: Bool = false) -> LocalModelEntry {
        var descriptor = testModel(id: id, source: .gguf, installed: false)
        descriptor.sizeBytes = mb * 1_000_000
        var entry = LocalModelEntry(descriptor: descriptor, summary: "", tags: [], fit: fit, isUserAdded: false)
        entry.unavailableReason = reason
        entry.isDeprecated = deprecated
        return entry
    }

    @Test func anInstalledDeviceModelIsUsedBeforeAnythingIsOffered() {
        let installed = testModel(id: "gguf/a/b", source: .gguf)
        let cloud = testModel(id: "anyrouter/x/y", source: .anyrouter)
        let plan = OfflineLogic.plan(models: [cloud, installed], catalog: [entry("big", mb: 900, fit: .fits)])
        #expect(plan == .use(installed))
    }

    @Test func withNothingInstalledTheSmallestModelThatRunsWellIsOffered() {
        let catalog = [
            entry("large", mb: 4000, fit: .fits), entry("small", mb: 800, fit: .fits), entry("tiny-tight", mb: 300, fit: .tight),
        ]
        #expect(OfflineLogic.plan(models: [], catalog: catalog) == .download(catalog[1]), "a tight model is only the fallback")
    }

    @Test func aModelOfUnknownSizeIsOfferedOnlyWhenNoSizedOneRunsWell() {
        var unknown = entry("unknown-size", mb: 1, fit: .fits)
        unknown.descriptor.sizeBytes = nil
        let sized = entry("sized", mb: 3000, fit: .fits)
        #expect(OfflineLogic.plan(models: [], catalog: [unknown, sized]) == .download(sized))
        #expect(OfflineLogic.plan(models: [], catalog: [sized, unknown]) == .download(sized))
        #expect(OfflineLogic.plan(models: [], catalog: [unknown]) == .download(unknown))
    }

    @Test func aTightModelIsOfferedWhenNothingRunsWell() {
        let catalog = [entry("a", mb: 2500, fit: .tight), entry("b", mb: 1800, fit: .tight)]
        #expect(OfflineLogic.plan(models: [], catalog: catalog) == .download(catalog[1]))
    }

    @Test func modelsThatCannotRunHereAreNeverOffered() {
        let catalog = [
            entry("wont", mb: 100, fit: .wontFit), entry("sim", mb: 100, fit: .fits, reason: "Needs a GPU"),
            entry("old", mb: 100, fit: .fits, deprecated: true), entry("unknown", mb: 100, fit: .unknown),
        ]
        #expect(OfflineLogic.plan(models: [testModel(id: "anyrouter/x/y", source: .anyrouter)], catalog: catalog) == .unavailable)
    }

    @Test func theMessagesNameTheModelAndTheSize() {
        let small = entry("small", mb: 800, fit: .fits)
        #expect(OfflineLogic.downloadQuestion(small).hasPrefix("Download "))
        #expect(OfflineLogic.downloadMessage(small).contains("Download size:"))
        var sizeless = small
        sizeless.descriptor.sizeBytes = nil
        #expect(!OfflineLogic.downloadMessage(sizeless).contains("Download size:"))
        #expect(OfflineLogic.downloadingMessage(small).contains("model menu"))
        #expect(OfflineLogic.usingMessage(testModel(source: .gguf)).contains("runs on this device"))
        #expect(OfflineLogic.nothingFitsMessage.contains("No model fits"))
    }

    // MARK: In the chat

    private func chat(tools: Bool) async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        var engine = ScriptedEngine(chunks: ["ok"])
        engine.models = [tools ? testModelWithTools() : testModel()]
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: nil, context: context, registry: registry,
                             settings: AppSettings(defaults: testDefaults()), models: models, toolHost: { _ in StubToolHost() })
    }

    @Test func askAboutTheClipboardFillsTheComposerAndNeverSends() async throws {
        let vm = try await chat(tools: false)
        let task = vm.run(.askClipboard, clipboardText: { "Meeting moved to 5pm" })
        #expect(task == nil)
        #expect(vm.input == "About this text:\nMeeting moved to 5pm\n\nMy question: ")
        #expect(vm.messages.isEmpty)
    }

    @Test func anEmptyClipboardSaysSoInsteadOfFillingNothing() async throws {
        let vm = try await chat(tools: false)
        vm.run(.askClipboard, clipboardText: { "  " })
        #expect(vm.input.isEmpty)
        #expect(vm.errorMessage == "Nothing copied yet.")
    }

    @Test func aCopiedLinkIsSummarizedByAModelWithTools() async throws {
        let vm = try await chat(tools: true)
        let task = vm.run(.summarizeLink, clipboardText: { "https://example.com/post" })
        await task?.value
        #expect(vm.messages.first?.content.hasSuffix("https://example.com/post") == true)
        #expect(vm.messages.count == 2)
    }

    @Test func aModelWithoutToolsKeepsTheLinkInTheFieldAndSaysWhy() async throws {
        let vm = try await chat(tools: false)
        let task = vm.run(.summarizeLink, clipboardText: { "https://example.com/post" })
        #expect(task == nil)
        #expect(vm.messages.isEmpty)
        #expect(vm.input.hasSuffix("https://example.com/post"))
        #expect(vm.errorMessage?.contains("cannot open links") == true)
    }

    @Test func withoutALinkTheComposerGetsTheLeadInToPasteInto() async throws {
        let vm = try await chat(tools: true)
        #expect(vm.run(.summarizeLink, clipboardText: { "plain words" }) == nil)
        #expect(vm.input == "Summarize this page:\n")
        #expect(vm.errorMessage == nil)
    }

    @Test func actionsThatNeedAPickerOrADialogAreLeftToTheComposer() async throws {
        let vm = try await chat(tools: true)
        #expect(vm.run(.readPhoto, clipboardText: { Issue.record("no clipboard"); return "" }) == nil)
        #expect(vm.run(.goOffline, clipboardText: { Issue.record("no clipboard"); return "" }) == nil)
        #expect(vm.input.isEmpty)
    }
}
