import Foundation
import Testing
@testable import AnyRouter

struct PasteOfferLogicTests {
    private let paragraph = "This sentence has a few mistakes in it, please fix them."

    @Test func aBlockPastedIntoAnEmptyComposerIsAPaste() {
        #expect(PasteOfferLogic.pastedText(from: "", to: paragraph) == paragraph)
    }

    @Test func aBlockPastedInTheMiddleOrAtTheEndIsFoundByItsPosition() {
        #expect(PasteOfferLogic.pastedText(from: "Check: ", to: "Check: " + paragraph) == paragraph)
        #expect(PasteOfferLogic.pastedText(from: "Check:  done", to: "Check: " + paragraph + " done") == paragraph)
    }

    @Test func typingAWordAtATimeIsNotAPaste() {
        var text = ""
        for word in ["Hello", " there,", " how", " are", " you", " today", " my", " friend"] {
            let next = text + word
            #expect(PasteOfferLogic.pastedText(from: text, to: next) == nil)
            text = next
        }
    }

    @Test func aShortPasteIsLeftAlone() {
        #expect(PasteOfferLogic.pastedText(from: "", to: String(repeating: "a", count: PasteOfferLogic.minInserted - 1)) == nil)
        #expect(PasteOfferLogic.pastedText(from: "", to: String(repeating: "a", count: PasteOfferLogic.minInserted)) != nil)
    }

    @Test func replacingOrDeletingTextIsNotAPaste() {
        #expect(PasteOfferLogic.pastedText(from: "old text here", to: paragraph) == nil, "the old text was replaced")
        #expect(PasteOfferLogic.pastedText(from: paragraph, to: "") == nil)
    }

    @Test func aBlockOfBlankLinesIsNotAPaste() {
        #expect(PasteOfferLogic.pastedText(from: "", to: String(repeating: "\n", count: 40)) == nil)
    }

    @Test func applyingAPresetPutsThePromptBeforeThePastedText() {
        let fix = PromptPreset(id: "fix", title: "Fix", prompt: "Fix this:\n", category: .write, symbol: "sparkles")
        #expect(PasteOfferLogic.apply(fix, to: "  " + paragraph + "\n") == "Fix this:\n" + paragraph)
        let plain = PromptPreset(id: "p", title: "P", prompt: "Summarize", category: .write, symbol: "sparkles")
        #expect(PasteOfferLogic.apply(plain, to: paragraph) == "Summarize\n\n" + paragraph)
    }

    @Test func aPresetThatEndsInALineBreakTakesText() {
        #expect(PasteOfferLogic.takesText(PromptPreset(id: "a", title: "A", prompt: "Text:\n", category: .write, symbol: "x")))
        #expect(!PasteOfferLogic.takesText(PromptPreset(id: "b", title: "B", prompt: "Plan my week", category: .plan, symbol: "x")))
    }
}

@MainActor
struct PasteOfferStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("presets-\(UUID().uuidString).json")
    }

    private func builtIns() -> [PromptPreset] {
        [
            PromptPreset(id: "fix", title: "Fix", prompt: "Fix:\n", category: .write, symbol: "sparkles", offerOnPaste: true),
            PromptPreset(id: "sum", title: "Sum", prompt: "Sum:\n", category: .write, symbol: "sparkles"),
            PromptPreset(id: "plan", title: "Plan", prompt: "Plan", category: .plan, symbol: "sparkles"),
        ]
    }

    @Test func aBuiltInFollowsItsDefaultUntilThePersonChoosesAndTheChoiceIsKept() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PresetStore(fileURL: url, builtIns: builtIns())
        #expect(store.pasteOffered.map(\.id) == ["fix"])
        store.setOffersOnPaste("sum", true)
        store.setOffersOnPaste("fix", false)
        #expect(store.pasteOffered.map(\.id) == ["sum"])
        let reloaded = PresetStore(fileURL: url, builtIns: builtIns())
        #expect(reloaded.pasteOffered.map(\.id) == ["sum"])
    }

    @Test func aCustomPresetCarriesItsOwnFlag() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PresetStore(fileURL: url, builtIns: builtIns())
        let mine = store.add(title: "Mine", prompt: "Do:\n", category: .write)
        #expect(!store.offersOnPaste(mine))
        store.setOffersOnPaste(mine.id, true)
        #expect(store.pasteOffered.map(\.title) == ["Mine", "Fix"], "custom presets come first")
        #expect(PresetStore(fileURL: url, builtIns: builtIns()).pasteOffered.map(\.title) == ["Mine", "Fix"])
    }

    @Test func aHiddenBuiltInIsNotOffered() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = PresetStore(fileURL: url, builtIns: builtIns())
        store.setBuiltInHidden("fix", hidden: true)
        #expect(store.pasteOffered.isEmpty)
    }

    @Test func aFileSavedBeforePasteOffersExistedStillLoads() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let old = """
        {"custom":[{"id":"custom-1","title":"Mine","prompt":"Do it","category":"write","symbol":"sparkles"}],"hiddenBuiltIns":["plan"]}
        """
        try Data(old.utf8).write(to: url)
        let store = PresetStore(fileURL: url, builtIns: builtIns())
        #expect(store.saveError == nil, "the file was read, not set aside")
        #expect(store.custom.map(\.title) == ["Mine"])
        #expect(store.custom.first?.offerOnPaste == false)
        #expect(store.hiddenBuiltIns == ["plan"])
        #expect(store.pasteChoices.isEmpty)
    }

    @Test func aPresetDecodesWithOrWithoutTheFlag() throws {
        let json = Data(#"{"id":"a","title":"A","prompt":"P","category":"code","symbol":"x","offerOnPaste":true}"#.utf8)
        #expect(try JSONDecoder().decode(PromptPreset.self, from: json).offerOnPaste)
        let encoded = try JSONEncoder().encode(PromptPreset(id: "a", title: "A", prompt: "P", category: .code, symbol: "x"))
        #expect(try JSONDecoder().decode(PromptPreset.self, from: encoded).offerOnPaste == false)
    }

    /// Every starter card has a second line: the bundled ones from presets.json, the person's own from what they do.
    @Test func everyBundledPresetHasACardDetailAndOlderPresetsFallBack() throws {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        #expect(!items.isEmpty)
        for item in items { #expect(!item.detail.isEmpty, "\(item.id) has no detail in presets.json") }
        #expect(items.first { $0.id == "quiz-me" }?.cardDetail == "on world geography")

        let json = Data(#"{"id":"a","title":"A","prompt":"Plan my day\nwith breaks","category":"plan","symbol":"x"}"#.utf8)
        let saved = try JSONDecoder().decode(PromptPreset.self, from: json)
        #expect(saved.detail.isEmpty, "a preset saved before the field existed still loads")
        #expect(saved.cardDetail == "Plan my day")
        let useCase = PromptPreset(id: "o", title: "O", prompt: "", category: .plan, symbol: "x", action: .goOffline)
        #expect(useCase.cardDetail == PresetAction.goOffline.summary)
        #expect(PromptPreset(id: "e", title: "E", prompt: "", category: .plan, symbol: "x").cardDetail.isEmpty)

        var mine = PromptPreset(id: "m", title: "M", prompt: "P", category: .plan, symbol: "x")
        mine.detail = "my own line"
        let reread = try JSONDecoder().decode(PromptPreset.self, from: JSONEncoder().encode(mine))
        #expect(reread.cardDetail == "my own line")
    }

    @Test func theBundledFixEnglishPresetIsOfferedByDefault() throws {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        #expect(items.first { $0.id == InboundPreset.fixEnglish }?.offerOnPaste == true)
        #expect(Set(items.filter(\.offerOnPaste).map(\.id)) == [InboundPreset.fixEnglish, "translate", "summarize", "reply-to-this"])
    }
}
