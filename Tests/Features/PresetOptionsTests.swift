import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct PresetOptionsTests {
    private func reply() throws -> PromptPreset {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        return try #require(items.first { $0.id == "reply-to-this" })
    }

    private func option(_ preset: PromptPreset, _ id: String) throws -> PresetOption {
        try #require(preset.options?.first { $0.id == id })
    }

    @Test func replyToThisOffersTheFourTonesAndThreeLanguages() throws {
        let preset = try reply()
        #expect(try option(preset, "tone").choices.map(\.title) == ["Polite", "Short", "Friendly", "Formal"])
        #expect(try option(preset, "language").choices.map(\.title) == ["Same", "English", "Vietnamese"])
        #expect(preset.hasOptions)
    }

    @Test func everyPlaceholderInAShippedPromptHasAnOptionAndEveryOptionAPlaceholder() throws {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        for preset in items {
            let placeholders = Set(preset.prompt.components(separatedBy: "{").dropFirst().compactMap { $0.components(separatedBy: "}").first })
            #expect(placeholders == Set((preset.options ?? []).map(\.id)), "\(preset.id)")
            for option in preset.options ?? [] {
                #expect(!option.choices.isEmpty, "\(preset.id) \(option.id)")
                #expect(Set(option.choices.map(\.id)).count == option.choices.count, "\(preset.id) \(option.id)")
            }
        }
    }

    @Test func defaultsAreTheFirstChoices() throws {
        let prompt = try reply().resolvedPrompt
        #expect(prompt.contains("Tone: polite and respectful."))
        #expect(prompt.contains("Language: the same language as the message."))
        #expect(!prompt.contains("{"))
    }

    @Test func eachPickChangesOnlyItsOwnWords() throws {
        let preset = try reply()
        var selection = PresetSelection()
        selection.pick("formal", for: try option(preset, "tone"))
        selection.pick("vietnamese", for: try option(preset, "language"))
        let prompt = PresetOptionsLogic.prompt(preset, selection: selection)
        #expect(prompt.contains("Tone: formal and professional."))
        #expect(prompt.contains("Language: Vietnamese."))
        #expect(prompt.hasSuffix("Message:\n"))
    }

    @Test func anUnknownPickFallsBackToTheDefault() throws {
        let preset = try reply()
        var selection = PresetSelection()
        selection.pick("gone", for: try option(preset, "tone"))
        #expect(selection.choice(for: try option(preset, "tone")).id == "polite")
    }

    @Test func aPresetWithoutOptionsKeepsItsPrompt() {
        let plain = PromptPreset(id: "p", title: "T", prompt: "Hello {x}", category: .write, symbol: "sparkles")
        #expect(!plain.hasOptions)
        #expect(plain.resolvedPrompt == "Hello {x}")
        #expect(PresetOptionsLogic.summary(plain) == "Hello {x}")
        var empty = plain
        empty.options = []
        #expect(!empty.hasOptions)
    }

    @Test func theMessageFollowsThePromptAndOnlyTheReplyIsAsked() throws {
        let preset = try reply()
        var selection = PresetSelection()
        selection.pick("short", for: try option(preset, "tone"))
        let text = PresetOptionsLogic.composerText(preset, selection: selection, message: "  Can you come at 5? \n")
        #expect(text.contains("short and to the point"))
        #expect(text.hasSuffix("Message:\nCan you come at 5?"))
        #expect(text.contains("Give the reply text only"))
    }

    @Test func chipsSayWhichChoicesTheyAskFor() throws {
        #expect(PresetOptionsLogic.summary(try reply()) == "Choose tone and language")
    }

    @Test func presetsWithPickersStayInTheRowWhateverTheShuffle() throws {
        let preset = try reply()
        let others = (0..<12).map { PromptPreset(id: "p\($0)", title: "T", prompt: "P", category: .write, symbol: "sparkles") }
        for seed in 0..<6 {
            let row = PresetLogic.featured(others + [preset], customIDs: ["p3"], category: nil, seed: UInt64(seed), limit: 4)
            #expect(row.map(\.id).prefix(2) == ["p3", "reply-to-this"])
        }
    }

    @Test func aPresetFileWithoutOptionsStillDecodes() throws {
        let json = Data(##"[{"id":"a","title":"A","prompt":"P","category":"write","symbol":"sparkles"}]"##.utf8)
        let items = try JSONDecoder().decode([PromptPreset].self, from: json)
        #expect(items.first?.options == nil)
    }

    // MARK: Chat

    private func chat() async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["Sure, 5 works."]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: nil, context: context, registry: registry,
                             settings: AppSettings(defaults: testDefaults()), models: models)
    }

    @Test func tappingAPresetWithPickersAsksForChoicesInsteadOfFillingTheComposer() async throws {
        let vm = try await chat()
        vm.input = "typed already"
        vm.usePreset(try reply())
        #expect(vm.presetNeedingChoices?.id == "reply-to-this")
        #expect(vm.input == "typed already")
        #expect(vm.focusTick == 0)
    }

    @Test func confirmingTheChoicesSendsThePromptWithTheMessage() async throws {
        let vm = try await chat()
        let preset = try reply()
        vm.usePreset(preset)
        var selection = PresetSelection()
        selection.pick("friendly", for: try option(preset, "tone"))
        await vm.finishChoices(preset, selection: selection, message: "Dinner at 5?")?.value
        #expect(vm.presetNeedingChoices == nil)
        #expect(vm.messages.map(\.role) == [.user, .assistant])
        let sent = try #require(vm.messages.first?.content)
        #expect(sent.contains("warm and friendly"))
        #expect(sent.hasSuffix("Message:\nDinner at 5?"))
    }

    @Test func aPastedMessageOffersReplyAndAsksForTheToneWithThePasteAsTheMessage() async throws {
        let preset = try reply()
        #expect(preset.offerOnPaste)
        let vm = try await chat()
        let pasted = "Can you join the planning call tomorrow at five?"
        vm.input = pasted
        vm.inputChanged(from: "", to: pasted)
        #expect(vm.pasteOffered)

        vm.applyToPaste(preset)
        #expect(vm.presetNeedingChoices?.id == "reply-to-this")
        #expect(!vm.pasteOffered)
        #expect(vm.input == pasted, "the sheet takes the pasted text as its message")
    }

    @Test func sendNowAndShortcutsUseTheDefaultChoices() async throws {
        let vm = try await chat()
        let preset = try reply()
        await vm.sendNow(preset)?.value
        #expect(vm.messages.first?.content == preset.resolvedPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(InboundChatLogic.composerText(preset: preset, text: "Hi") == preset.resolvedPrompt + "Hi")
    }
}
