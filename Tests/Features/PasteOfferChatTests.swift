import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// What the composer does with a paste: offer presets, and stop offering when the text moves on.
@MainActor
struct PasteOfferChatTests {
    private let paragraph = "This sentence has a few mistakes in it, please fix them."
    private let fix = PromptPreset(id: "fix", title: "Fix", prompt: "Fix this:\n", category: .write, symbol: "sparkles", offerOnPaste: true)

    private func chat() async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["ok"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models)
    }

    /// What the composer view does: the field changes, then onChange reports old and new.
    private func type(_ vm: ChatViewModel, _ text: String) {
        let old = vm.input
        vm.input = text
        vm.inputChanged(from: old, to: text)
    }

    @Test func aPasteIntoAnEmptyComposerOffersPresets() async throws {
        let vm = try await chat()
        type(vm, paragraph)
        #expect(vm.pasteOffered)
    }

    @Test func theNextEditThatIsNotAPasteHidesTheOffer() async throws {
        let vm = try await chat()
        type(vm, paragraph)
        type(vm, paragraph + " Thanks")
        #expect(!vm.pasteOffered)
    }

    @Test func aSecondPasteKeepsOffering() async throws {
        let vm = try await chat()
        type(vm, paragraph)
        type(vm, paragraph + "\n" + paragraph)
        #expect(vm.pasteOffered)
    }

    @Test func clearingTheFieldOrSendingHidesTheOffer() async throws {
        let vm = try await chat()
        type(vm, paragraph)
        type(vm, "")
        #expect(!vm.pasteOffered)
        type(vm, paragraph)
        await vm.send()?.value
        vm.inputChanged(from: paragraph, to: vm.input)
        #expect(!vm.pasteOffered)
    }

    @Test func aPresetFilledByTheAppIsNotAPaste() async throws {
        let vm = try await chat()
        let old = vm.input
        vm.usePreset(fix)
        vm.inputChanged(from: old, to: vm.input)
        #expect(!vm.pasteOffered)
        #expect(vm.input == "Fix this:\n")
    }

    @Test func tappingAPresetAppliesItToThePastedTextAndHidesTheOffer() async throws {
        let vm = try await chat()
        type(vm, paragraph)
        let before = vm.focusTick
        vm.applyToPaste(fix)
        #expect(vm.input == "Fix this:\n" + paragraph)
        #expect(!vm.pasteOffered)
        #expect(vm.focusTick == before + 1)
        // The change that follows is the app's own text, not a second paste.
        vm.inputChanged(from: paragraph, to: vm.input)
        #expect(!vm.pasteOffered)
    }

    @Test func theCloseButtonHidesTheOffer() async throws {
        let vm = try await chat()
        type(vm, paragraph)
        vm.dismissPasteOffer()
        #expect(!vm.pasteOffered)
    }

    @Test func anInboundRequestFillsTheComposerWithoutOfferingPresets() async throws {
        let vm = try await chat()
        let old = vm.input
        vm.start(InboundChat(text: paragraph), preset: fix)
        vm.inputChanged(from: old, to: vm.input)
        #expect(vm.input == "Fix this:\n" + paragraph)
        #expect(!vm.pasteOffered)
    }
}
