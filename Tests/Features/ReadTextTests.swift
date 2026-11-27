import Foundation
import SwiftData
import Testing
import Vision
@testable import AnyRouter

private final class ReceiptFixtureAnchor {}

private func receiptFixture() throws -> Data {
    let url = try #require(Bundle(for: ReceiptFixtureAnchor.self).url(forResource: "receipt", withExtension: "png"))
    return try Data(contentsOf: url)
}

private func folded(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
}

@MainActor
struct ReadTextTests {
    // MARK: Pure logic

    @Test func languagesFollowThePreferredOrderAndOnlyKeepSupportedOnes() {
        #expect(OCRLogic.languages(supported: ["en-US", "fr-FR", "vi-VT"]) == ["vi-VT", "en-US"])
        #expect(OCRLogic.languages(supported: ["vi-VN", "en-US"]) == ["vi-VN", "en-US"], "the standard code works if a system uses it")
        #expect(OCRLogic.languages(supported: ["vi-VT", "vi-VN", "en-US"]) == ["vi-VT", "en-US"], "one Vietnamese code")
        #expect(OCRLogic.languages(supported: ["en-US", "fr-FR"]) == ["en-US"])
        #expect(OCRLogic.languages(supported: []).isEmpty)
    }

    @Test func documentRecognitionAsksForVietnameseThenEnglish() {
        #expect(OCRLogic.documentLanguageIndexes(codes: ["fr", "en", nil, "vi", "en"]) == [3, 1])
        #expect(OCRLogic.documentLanguageIndexes(codes: ["en"]) == [0])
        #expect(OCRLogic.documentLanguageIndexes(codes: ["fr", nil]).isEmpty)
    }

    @Test func eachScanIsItsOwnItem() {
        let first = ScannedText(text: "a")
        #expect(first == first)
        #expect(first != ScannedText(text: "a"), "two scans of the same text are two sheets")
    }

    @Test func photosAreJoinedAndAScanGoesUnderWhatWasTyped() {
        #expect(OCRLogic.join(["one", "two"]) == "one\n\ntwo")
        #expect(OCRLogic.appended("scan", to: "  ") == "scan")
        #expect(OCRLogic.appended("scan", to: "Look at this\n") == "Look at this\n\nscan")
    }

    @Test func theScanPresetsAreShippedAndAskForTheirChoices() throws {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        let scan = OCRLogic.scanPresetIDs.compactMap { id in items.first { $0.id == id } }
        #expect(scan.map(\.title) == ["Translate", "Split this bill", "Summarize text"])
        let translate = scan[0]
        var selection = PresetSelection()
        let language = try #require(translate.options?.first)
        #expect(language.choices.map(\.id).contains("vietnamese") && language.choices.map(\.id).contains("english"))
        selection.pick("vietnamese", for: language)
        #expect(PresetOptionsLogic.prompt(translate, selection: selection).contains("into Vietnamese."))
        #expect(scan[1].resolvedPrompt.contains("between 2 people, with no tip."))
    }

    // MARK: Vision on the fixture image

    @Test func visionOnThisSystemKnowsBothLanguagesWeAskFor() throws {
        // The real list, not a copy of it: a wrong code would be dropped by Vision without an error.
        let supported = try VNRecognizeTextRequest().supportedRecognitionLanguages()
        let languages = OCRLogic.languages(supported: supported)
        #expect(languages.count == 2, "Vietnamese and English must both be in Vision's list: \(supported)")
        #expect(languages.last == "en-US")
    }

    @Test func theReceiptPhotoIsRead() throws {
        let text = try #require(TextExtraction.ocr(try receiptFixture()))
        #expect(text.contains("TOTAL"))
        #expect(text.contains("80,000"))
        #expect(folded(text).contains("cam on"), "Vietnamese line: \(text)")
    }

    @Test func onlyPhotosWithTextCount() async throws {
        let texts = await TextExtraction.texts(inImages: [pngData(width: 300, height: 200), try receiptFixture(), Data("nope".utf8)])
        #expect(texts.count == 1)
        #expect(texts.first?.contains("CAFE SAIGON") == true)
    }

    // MARK: Chat

    private func chat() async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["ok"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: nil, context: context, registry: registry,
                             settings: AppSettings(defaults: testDefaults()), models: models)
    }

    @Test func readingAPhotoOpensTheScanWithoutAttachingIt() async throws {
        let vm = try await chat()
        vm.readText(from: [try receiptFixture()])
        #expect(vm.ingesting == 1)
        // Vision can take seconds on a busy CI simulator: wait for the scan task, not a polling budget.
        await vm.finishIngesting()
        #expect(vm.scannedText != nil)
        #expect(vm.scannedText?.text.contains("TOTAL") == true)
        #expect(vm.ingesting == 0)
        #expect(vm.pending.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func aPhotoWithoutTextSaysSo() async throws {
        let vm = try await chat()
        vm.readText(from: [pngData(width: 300, height: 200)])
        await vm.finishIngesting()
        #expect(vm.errorMessage == OCRLogic.noTextMessage)
        #expect(vm.scannedText == nil)
        #expect(vm.ingesting == 0)
    }

    @Test func noPhotosDoNothing() async throws {
        let vm = try await chat()
        vm.readText(from: [])
        #expect(vm.ingesting == 0 && vm.scannedText == nil && vm.errorMessage == nil)
    }

    @Test func aScanGoesIntoTheComposerWithOrWithoutAPreset() async throws {
        let vm = try await chat()
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        let translate = try #require(items.first { $0.id == "translate" })
        vm.scannedText = ScannedText(text: "Xin chao")

        vm.useScan(nil, selection: PresetSelection(), text: "Xin chao")
        #expect(vm.scannedText == nil)
        #expect(vm.input == "Xin chao")
        #expect(vm.focusTick == 1)

        vm.input = ""
        var selection = PresetSelection()
        selection.pick("english", for: try #require(translate.options?.first))
        vm.useScan(translate, selection: selection, text: "Xin chao")
        #expect(vm.input.hasPrefix("Translate the text below into English."))
        #expect(vm.input.hasSuffix("Text:\nXin chao"))
        #expect(vm.messages.isEmpty, "the composer is filled, nothing is sent")
    }

    @Test func aScanThePhotoFilledInIsNotTreatedAsAPaste() async throws {
        let vm = try await chat()
        let long = "CAFE SAIGON Pho bo 65,000 Tra da 15,000 TOTAL 80,000"
        vm.useScan(nil, selection: PresetSelection(), text: long)
        vm.inputChanged(from: "", to: vm.input)
        #expect(!vm.pasteOffered)
    }
}
