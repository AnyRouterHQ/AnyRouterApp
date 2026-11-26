import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct AttachmentChatTests {
    private struct Rig {
        let vm: ChatViewModel
        let temp: TempAttachments
        let models: ModelStore
        let context: ModelContext
        let container: ModelContainer
    }

    private func rig(models: [ModelDescriptor] = [testModel()]) async throws -> Rig {
        let container = try ModelContainer.anyRouter(inMemory: true)
        let context = ModelContext(container)
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(models: models, chunks: ["ok"]))
        let store = ModelStore(registry: registry, defaults: testDefaults())
        await store.refresh()
        let temp = TempAttachments()
        let vm = ChatViewModel(thread: nil, context: context, registry: registry,
                               settings: AppSettings(defaults: testDefaults()), models: store, attachments: temp.store)
        return Rig(vm: vm, temp: temp, models: store, context: context, container: container)
    }

    private func settle(_ vm: ChatViewModel) async throws {
        for _ in 0..<250 where vm.ingesting > 0 { try await Task.sleep(for: .milliseconds(20)) }
    }

    private func textFile(_ name: String = "notes.txt", _ text: String = "Pick up the keys.") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "c-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func aFileShowsAsPendingAndAloneItCanBeSent() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        #expect(!r.vm.canSend)
        r.vm.attachFiles([try textFile()])
        #expect(r.vm.ingesting == 1 && !r.vm.canSend)
        try await settle(r.vm)
        #expect(r.vm.pending.map(\.filename) == ["notes.txt"] && r.vm.canSend)

        await r.vm.send()?.value
        let user = try #require(r.vm.messages.first)
        #expect(user.content.isEmpty && user.attachments.count == 1)
        #expect(r.vm.pending.isEmpty)
        #expect(r.vm.thread?.title == "notes.txt")
        let kept = try #require(user.attachments.first)
        #expect(kept.relativePath.hasPrefix(try #require(r.vm.thread?.id.uuidString) + "/"))
        #expect(r.temp.exists(kept))
        #expect(kept.extractedText == "Pick up the keys.")
    }

    @Test func aMessageWithTextAndAFileKeepsBoth() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        r.vm.attachFiles([try textFile()])
        try await settle(r.vm)
        r.vm.input = "Summarise this"
        await r.vm.send()?.value
        #expect(r.vm.messages.first?.content == "Summarise this")
        #expect(r.vm.thread?.title == "Summarise this")
        #expect(r.vm.messages.first?.attachments.count == 1)
    }

    @Test func removingAPendingFileDeletesIt() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        r.vm.attachFiles([try textFile()])
        try await settle(r.vm)
        let file = try #require(r.vm.pending.first)
        r.vm.removePending(file)
        #expect(r.vm.pending.isEmpty && !r.temp.exists(file))
        r.vm.removePending(file)
        #expect(r.vm.pending.isEmpty)
    }

    @Test func aFileThatCannotBeSentStaysPendingMarkedAndNothingIsSent() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        r.vm.attachFiles([try textFile("good.txt"), try textFile("bad.txt")])
        try await settle(r.vm)
        let bad = try #require(r.vm.pending.first { $0.filename == "bad.txt" })
        r.temp.store.remove(bad)
        r.vm.input = "Read both"
        #expect(r.vm.send() == nil)
        #expect(r.vm.thread == nil && r.vm.messages.isEmpty)
        #expect(r.vm.input == "Read both")
        #expect(r.vm.pending.count == 2 && r.vm.failedAttachmentIDs == [bad.id])
        #expect(r.vm.errorMessage?.contains("bad.txt") == true)
        let good = try #require(r.vm.pending.first { $0.filename == "good.txt" })
        #expect(r.temp.exists(good) && good.relativePath.hasPrefix("_pending/"))

        r.vm.removePending(bad)
        #expect(r.vm.failedAttachmentIDs.isEmpty)
        await r.vm.send()?.value
        #expect(r.vm.messages.first?.attachments.map(\.filename) == ["good.txt"])
        #expect(r.vm.messages.first?.attachments.first.map(r.temp.exists) == true)
    }

    @Test func aMoveThatFailsAfterTheCheckKeepsEveryFilePendingToo() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        r.vm.attachFiles([try textFile("a.txt")])
        try await settle(r.vm)
        // A plain file where the thread folder must go: creating the folder fails.
        try FileManager.default.createDirectory(at: r.temp.store.root, withIntermediateDirectories: true)
        try Data().write(to: r.temp.store.root.appending(path: r.vm.draftThreadID.uuidString))
        #expect(r.vm.send() == nil)
        #expect(r.vm.pending.map(\.filename) == ["a.txt"] && r.vm.failedAttachmentIDs.count == 1)
        #expect(r.vm.thread == nil)
    }

    @Test func atMostTenFilesGoInOneMessage() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        r.vm.attachFiles(try (0..<11).map { try textFile("f\($0).txt") })
        try await settle(r.vm)
        #expect(r.vm.pending.count == AttachmentLogic.maxPerMessage)
        #expect(r.vm.errorMessage?.contains("up to 10") == true)
        r.vm.attachFiles([try textFile("extra.txt")])
        #expect(r.vm.ingesting == 0 && r.vm.pending.count == 10)
    }

    @Test func aFileTheAppCannotReadIsReportedAndNotKept() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        r.vm.attachFiles([try textFile("a.zip", "x")])
        try await settle(r.vm)
        #expect(r.vm.pending.isEmpty && r.vm.errorMessage == "a.zip is not a type the app can read.")
    }

    @Test func photosAreAddedFromTheirBytes() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        r.vm.attachImages([(data: pngData(width: 100, height: 100), filename: "Photo 1.jpg")])
        try await settle(r.vm)
        #expect(r.vm.pending.first?.kind == .image)
    }

    @Test func aTextOnlyModelGetsANoteAndAVisionModelIsOffered() async throws {
        let sees = ModelDescriptor(id: "apple/eyes", source: .apple, displayName: "Eyes", contextLength: nil,
                                   capabilities: ["chat", "vision"], sizeBytes: nil, isInstalled: true)
        let r = try await rig(models: [testModel(id: "apple/foundation"), sees])
        defer { r.temp.cleanup() }
        r.vm.choose(testModel(id: "apple/foundation"))
        #expect(r.vm.attachmentNote == nil && r.vm.visionAlternative == nil)
        r.vm.attachImages([(data: pngData(width: 100, height: 100), filename: "p.png")])
        try await settle(r.vm)
        #expect(r.vm.model?.id == "apple/foundation")
        #expect(r.vm.attachmentNote == AttachmentLogic.visionNote)
        #expect(r.vm.visionAlternative?.id == "apple/eyes")
        r.vm.switchToVisionModel()
        #expect(r.vm.model?.id == "apple/eyes")
        #expect(r.vm.attachmentNote == nil)
        r.vm.switchToVisionModel()
        #expect(r.vm.model?.id == "apple/eyes")
    }

    @Test func noteWithoutAnyVisionModelOffersNoSwitch() async throws {
        let r = try await rig()
        defer { r.temp.cleanup() }
        r.vm.attachImages([(data: pngData(width: 100, height: 100), filename: "p.png")])
        try await settle(r.vm)
        #expect(r.vm.attachmentNote != nil && r.vm.visionAlternative == nil)
        r.vm.switchToVisionModel()
        #expect(r.vm.model?.id == "apple/foundation")
    }

    @Test func aVisionModelShowsAnEyeInThePicker() {
        let plain = testModel(id: "apple/foundation")
        var sees = plain
        sees.capabilities.insert("vision")
        #expect(!PickerRow.make(plain).supportsVision)
        #expect(PickerRow.make(sees).supportsVision)
        var cloud = sees
        cloud.source = .anyrouter
        cloud.id = "anyrouter/x/y"
        #expect(PickerRow.make(cloud).supportsVision)
    }
}
