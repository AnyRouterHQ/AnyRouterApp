import Foundation
import Testing
import UIKit
@testable import AnyRouter

private final class ExtractFixtureAnchor {}

private func receiptPhoto() throws -> Data {
    let url = try #require(Bundle(for: ExtractFixtureAnchor.self).url(forResource: "receipt", withExtension: "png"))
    return try Data(contentsOf: url)
}

private struct FakeReader: ImageTextReading {
    var text = "device text"
    var failure: String?

    func read(_ image: Data) async throws -> ImageText {
        if let failure { throw TestFailure(message: failure) }
        return ImageText(text: text)
    }
}

private func pdf(_ text: String?) -> Data {
    UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 300)).pdfData { context in
        context.beginPage()
        text?.draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
    }
}

@MainActor
struct ExtractSessionTests {
    private let reply = ##"[{"name":"Merchant","value":"Cafe Saigon","quote":"cafe saigon"},{"name":"Total","value":"80,000","quote":"TOTAL 80,000"}]"##

    private func make(reply: [String] = [], reader: FakeReader? = FakeReader()) async throws -> (ExtractSession, ScriptedEngine) {
        let registry = EngineRegistry()
        let engine = ScriptedEngine(chunks: reply)
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        models.select(try #require(models.models.first))
        let presets = PresetStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "presets-\(UUID().uuidString).json"), builtIns: [])
        let chat = HeadlessChat(registry: registry, models: models, presets: presets)
        let session = ExtractSession(picks: MiniAppModelPicks(defaults: testDefaults()))
        session.models = models
        session.ask = { try await chat.ask($0, modelID: $1) }
        if let reader { session.deviceReader = reader }
        return (session, engine)
    }

    // MARK: Fixture

    @Test func theReceiptPhotoReadByVisionIsExtractedThroughAScriptedModel() async throws {
        let (session, engine) = try await make(reply: [reply], reader: nil)
        await session.load(images: [try receiptPhoto()], name: "receipt.png")
        #expect(session.errorMessage == nil)
        #expect(session.text.contains("TOTAL"))

        await session.extract()
        #expect(session.errorMessage == nil)
        let prompt = try #require(engine.messagesSeen.lastTexts.last)
        #expect(prompt.contains("- Merchant (text)") && prompt.contains("CAFE SAIGON"))

        func quoted(_ name: String) -> String? {
            session.fields.first { $0.name == name }?.source.flatMap { ExtractLogic.stringRange($0, in: session.text) }
                .map { String(session.text[$0]) }
        }
        #expect(quoted("Merchant") == "CAFE SAIGON", "the quote was lower case, the receipt's words keep their case")
        #expect(quoted("Total")?.contains("80,000") == true)
        #expect(session.fields.first { $0.name == "Date" }?.source == nil)
        #expect(session.fields.map(\.name) == ["Merchant", "Date", "Total", "Tax", "Payment method"])
    }

    // MARK: Reading

    @Test func aPhotoIsReadOnTheDeviceByDefault() async throws {
        let (session, _) = try await make()
        session.cloudReader = { _ in FakeReader(text: "cloud text") }
        await session.load(images: [Data([1]), Data([2])], name: "Photos")
        #expect(session.text == "device text\n\ndevice text")
        #expect(session.sourceName == "Photos")
        #expect(session.phase == .idle)
    }

    @Test func theSwitchSendsTheImageToTheCloudReaderAndSignedOutKeepsItOnTheDevice() async throws {
        let (session, _) = try await make()
        let name = LockedBox<String?>(nil)
        session.cloudReader = { file in
            name.value = file
            return FakeReader(text: "cloud text")
        }
        session.usesCloudReader = true
        await session.load(images: [Data([1])], name: "bill.jpg")
        #expect(session.text == "cloud text")
        #expect(name.value == "bill.jpg")

        session.cloudReader = { _ in nil }
        await session.load(images: [Data([1])], name: "bill.jpg")
        #expect(session.text == "device text", "no cloud reader (signed out) means the device reads it")
    }

    @Test func aPhotoWithoutTextAndAFailingReaderEachSayWhy() async throws {
        let (session, _) = try await make(reader: FakeReader(text: "  "))
        await session.load(images: [Data([1])], name: "blank.png")
        #expect(session.text.isEmpty)
        #expect(session.errorMessage == OCRLogic.noTextMessage)

        session.deviceReader = FakeReader(failure: "Vision is busy")
        await session.load(images: [Data([1])], name: "blank.png")
        #expect(session.errorMessage == "Vision is busy")
        #expect(session.phase == .idle)
    }

    @Test func aPdfWithATextLayerNeedsNoReader() async throws {
        let (session, _) = try await make(reader: FakeReader(failure: "must not be used"))
        await session.load(pdf: pdf("Invoice 42 Total 9.50"), name: "a.pdf")
        #expect(session.text.contains("Invoice 42"))
        #expect(session.errorMessage == nil)
    }

    @Test func aScannedPdfHasItsPagesReadAsImages() async throws {
        let (session, _) = try await make(reader: FakeReader(text: "scanned page"))
        await session.load(pdf: pdf(nil), name: "scan.pdf")
        #expect(session.text == "scanned page")
        let pages = await PDFPageImages.render(pdf(nil))
        #expect(pages.count == 1)
        #expect(await PDFPageImages.render(Data("nope".utf8)).isEmpty)
    }

    @Test func aSeedAndAFileOpenLikeAPhotoOrAPdf() async throws {
        let (session, _) = try await make()
        await session.load(ExtractSeed(data: Data([1]), filename: "Photo.jpg", isPDF: false))
        #expect(session.text == "device text" && session.sourceName == "Photo.jpg")
        await session.load(ExtractSeed(data: pdf("Hello pdf"), filename: "a.pdf", isPDF: true))
        #expect(session.text.contains("Hello pdf"))

        let folder = FileManager.default.temporaryDirectory.appending(path: "extract-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appending(path: "bill.PNG")
        try Data([1, 2]).write(to: photo)
        await session.load(file: photo)
        #expect(session.text == "device text" && session.sourceName == "bill.PNG")
        let document = folder.appending(path: "bill.PDF")
        try pdf("From a file").write(to: document)
        await session.load(file: document)
        #expect(session.text.contains("From a file"))

        await session.load(file: folder.appending(path: "missing.png"))
        #expect(session.errorMessage == "The file could not be opened.")
    }

    // MARK: Extract

    @Test func theReplyBecomesFieldsLinkedToTheText() async throws {
        let (session, engine) = try await make(reply: [reply])
        session.applyDemo(stage: "document")
        await session.extract()
        #expect(session.fields.map(\.value) == ["Cafe Saigon", "", "80,000", "", ""])
        #expect(session.fields.first?.source == 0..<11)
        #expect(session.sourceRanges.count == 2)
        #expect(session.phase == .idle)
        #expect(engine.usedModels.values == ["apple/foundation"])
    }

    /// The preset prefers the AnyRouter router; signed out it is not listed, so the fallback, Apple, answers.
    @Test func signedOutThePresetFallsBackToAppleAndItAnswers() async throws {
        let (session, engine) = try await make(reply: [reply])
        session.applyDemo(stage: "document")
        #expect(session.preset.preferredModel == "anyrouter/auto" && session.preset.fallbackModel == "apple/foundation")
        #expect(session.resolvedModel?.id == "apple/foundation")
        await session.extract()
        #expect(engine.usedModels.values == ["apple/foundation"])
    }

    /// The picker's choice is remembered for Extract, and a pick that is gone falls back to the preset's models.
    @Test func thePickIsRememberedAndAGoneOneFallsBack() async throws {
        let defaults = testDefaults()
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(models: [testModel(id: "apple/foundation")]))
        registry.register(ScriptedEngine(source: .gguf, models: [testModel(id: "gguf/a/b.gguf", source: .gguf)]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let session = ExtractSession(picks: MiniAppModelPicks(defaults: defaults))
        session.models = models
        session.choose(try #require(models.models.first { $0.source == .gguf }))
        #expect(session.resolvedModel?.id == "gguf/a/b.gguf")
        let again = ExtractSession(picks: MiniAppModelPicks(defaults: defaults))
        again.models = models
        #expect(again.resolvedModel?.id == "gguf/a/b.gguf")
        defaults.set("gguf/missing/none", forKey: "miniApps.model.extract")
        let gone = ExtractSession(picks: MiniAppModelPicks(defaults: defaults))
        gone.models = models
        #expect(gone.resolvedModel?.id == "apple/foundation")
    }

    @Test func aModelThatAnswersWithProseOnlySaysSo() async throws {
        let (session, _) = try await make(reply: ["I cannot do that."])
        session.applyDemo(stage: "document")
        await session.extract()
        #expect(session.errorMessage == ExtractError.unreadable.errorDescription)
        #expect(session.fields.isEmpty)
    }

    @Test func noModelAndNoTextEachStopBeforeAskingAnything() async throws {
        let session = ExtractSession()
        await session.extract()
        #expect(session.errorMessage == nil, "nothing to extract yet")
        session.applyDemo(stage: "document")
        #expect(session.resolvedModel == nil && session.cutNote == nil)
        await session.extract()
        #expect(session.errorMessage == HeadlessError.noModel.message)
    }

    @Test func aLongDocumentIsCutForAPhoneModelAndSaysSo() async throws {
        let long = String(repeating: "x", count: 6_000) + "TAIL"
        let (session, engine) = try await make(reply: ["[]"], reader: FakeReader(text: long))
        await session.load(images: [Data([1])], name: "long.png")
        #expect(session.cutNote == "Only the first 6000 of 6004 characters are sent to this model.")
        await session.extract()
        let prompt = try #require(engine.messagesSeen.lastTexts.last)
        #expect(!prompt.contains("TAIL"))
        #expect(session.errorMessage == nil)
    }

    @Test func aShortDocumentHasNoCutNote() async throws {
        let (session, _) = try await make()
        session.applyDemo(stage: "document")
        #expect(session.cutNote == nil)
    }

    // MARK: Choices

    @Test func tappingAFieldSelectsItsSourceOnlyWhenItHasOne() async throws {
        let (session, _) = try await make()
        session.applyDemo(stage: "fields")
        session.select("Total")
        #expect(session.selectedFieldID == "Total")
        #expect(session.selectedRange == 40..<52)
        session.select("Tax")
        #expect(session.selectedFieldID == nil, "Not found in the text: nothing to mark")
        session.select("Nope")
        #expect(session.selectedFieldID == nil)
    }

    @Test func changingThePresetOrTheFieldsClearsTheAnswers() async throws {
        let (session, _) = try await make()
        session.applyDemo(stage: "selected")
        #expect(!session.fields.isEmpty && session.selectedFieldID == "Total")
        session.choosePreset("receipt")
        #expect(!session.fields.isEmpty, "the same preset keeps its answers")
        session.choosePreset("bill")
        #expect(session.fields.isEmpty && session.selectedFieldID == nil)
        #expect(session.activeFields.map(\.name).first == "Provider")
    }

    @Test func aCustomPresetStartsEmptyAndTakesFieldsTheUserAdds() async throws {
        let (session, _) = try await make()
        session.applyDemo(stage: "document")
        session.choosePreset("custom")
        #expect(session.activeFields.isEmpty && !session.canExtract)
        session.addCustomField(" Tip ")
        session.addCustomField("tip")
        session.addCustomField("Order number")
        #expect(session.activeFields.map(\.name) == ["Tip", "Order number"])
        #expect(session.canExtract)
        session.setKind(.money, ofCustomField: "Tip")
        session.setKind(.date, ofCustomField: "Nope")
        #expect(session.activeFields.map(\.kind) == [.money, .text])
        session.removeCustomFields(at: IndexSet(integer: 0))
        #expect(session.activeFields.map(\.name) == ["Order number"])
    }

    @Test func theDemoStagesBuildUp() async throws {
        let session = ExtractSession()
        session.applyDemo(stage: "empty")
        #expect(session.text.isEmpty)
        session.applyDemo(stage: "document")
        #expect(session.text == ExtractSession.demoText && session.fields.isEmpty)
        session.applyDemo(stage: "fields")
        #expect(session.fields.count == 5 && session.selectedFieldID == nil)
        #expect(ExtractLogic.note(for: try #require(session.fields.first { $0.name == "Tax" })) == "Not found in the text")
        #expect(ExtractLogic.note(for: try #require(session.fields.first { $0.name == "Date" })) == "No value in the text")
        session.applyDemo(stage: "selected")
        #expect(session.selectedFieldID == "Total")
        #expect(ExtractSession.demoStage == nil, "outside a demo run there is no stage")
    }

    @Test func theSessionLinesFollowTheText() {
        let session = ExtractSession()
        session.applyDemo(stage: "document")
        #expect(session.lines.count == 5)
    }
}

@MainActor
struct ExtractShellTests {
    private let seed = ExtractSeed(data: Data([1]), filename: "a.png", isPDF: false)

    @Test func theComposerOpensExtractWithItsFileOnceAndEveryOtherPlaceClosesIt() {
        let shell = ShellModel()
        shell.isSidebarOpen = true
        shell.presentExtract(seed: seed)
        #expect(shell.isExtractPresented && !shell.isSidebarOpen && !shell.isAppsPresented)
        #expect(shell.takeExtractSeed() == seed)
        #expect(shell.takeExtractSeed() == nil)

        shell.open(.apps, closeSidebar: false)
        #expect(!shell.isExtractPresented && shell.isAppsPresented)
        shell.open(.extract, closeSidebar: false)
        #expect(shell.isExtractPresented && !shell.isAppsPresented)
        shell.newChat(closeSidebar: false)
        #expect(!shell.isExtractPresented)
        shell.presentExtract(seed: nil)
        shell.select(threadID: UUID(), closeSidebar: false)
        #expect(!shell.isExtractPresented)
    }
}
