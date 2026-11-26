import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
@Suite(.serialized)
struct ShareHandoffTests {
    private func tempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "share-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func presetStore() throws -> PresetStore {
        PresetStore(fileURL: tempFolder().appending(path: "presets.json"),
                    builtIns: try PresetStore.bundled(bundle: Bundle(for: PresetStore.self)))
    }

    /// Saves a share with files the way the extension does.
    @discardableResult
    private func save(_ inbox: ShareInbox, text: String? = nil, url: String? = nil, files: [(SharedFile, Data)] = [],
                      action: ShareAction = .ask, at date: Date = Date()) throws -> SharedPayload {
        var payload = SharedPayload(createdAt: date, text: text, url: url, action: action)
        let folder = try inbox.prepare(payload.id)
        for (file, data) in files {
            try data.write(to: folder.appending(path: file.filename))
            payload.files.append(file)
        }
        try inbox.save(payload)
        return payload
    }

    // MARK: Inbox

    @Test func theInboxListsCompleteSharesOldestFirst() throws {
        let inbox = ShareInbox(root: tempFolder().appending(path: "ShareInbox"))
        let early = try save(inbox, text: "one", at: Date(timeIntervalSince1970: 1_000))
        let late = try save(inbox, text: "two", action: .summarize, at: Date(timeIntervalSince1970: 2_000))
        let unfinished = try inbox.prepare(UUID())
        #expect(FileManager.default.fileExists(atPath: unfinished.path))

        #expect(inbox.pending().map(\.id) == [early.id, late.id], "a folder without payload.json is still being written")
        #expect(inbox.pending().last?.action == .summarize)
    }

    @Test func anEmptyOrMissingInboxHasNothingPending() {
        #expect(ShareInbox(root: tempFolder().appending(path: "never-created")).pending().isEmpty)
    }

    @Test func discardingRemovesTheShareAndItsFiles() throws {
        let inbox = ShareInbox(root: tempFolder())
        let payload = try save(inbox, files: [(SharedFile(filename: "a.pdf", kind: .pdf), Data("x".utf8))])
        inbox.discard(payload)
        #expect(inbox.pending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: inbox.folder(for: payload.id).path))
    }

    @Test func claimingMovesTheFilesOutOfTheInbox() throws {
        let inbox = ShareInbox(root: tempFolder())
        let work = tempFolder().appending(path: "work")
        let payload = try save(inbox, files: [(SharedFile(filename: "a.pdf", kind: .pdf), Data("pdf".utf8))])

        let folder = try inbox.claim(payload, into: work)
        #expect(try Data(contentsOf: folder.appending(path: "a.pdf")) == Data("pdf".utf8))
        #expect(inbox.pending().isEmpty)

        let again = try save(inbox, files: [(SharedFile(filename: "b.pdf", kind: .pdf), Data("b".utf8))])
        let first = try inbox.claim(again, into: work)
        #expect(first.lastPathComponent == again.id.uuidString)
    }

    // MARK: Links

    @Test func aShortTextTravelsInALinkAndComesBackWithItsAction() throws {
        let url = try #require(ShareDeepLink.askURL(text: "Dinner at 5 & bring wine?", action: .reply))
        #expect(url.scheme == "anyrouter" && url.host == "ask")
        let link = try #require(ShareDeepLink.parse(url))
        #expect(link.text == "Dinner at 5 & bring wine?")
        #expect(link.action == .reply)
    }

    @Test func aLongOrEmptyTextCannotBeALink() {
        #expect(ShareDeepLink.askURL(text: "", action: .ask) == nil)
        #expect(ShareDeepLink.askURL(text: String(repeating: "a", count: ShareDeepLink.maxTextLength + 1), action: .ask) == nil)
        #expect(ShareDeepLink.askURL(text: String(repeating: "a", count: ShareDeepLink.maxTextLength), action: .ask) != nil)
    }

    @Test func onlyAnAskLinkWithTextIsParsed() throws {
        #expect(ShareDeepLink.parse(ShareDeepLink.shareURL) == nil)
        #expect(ShareDeepLink.parse(try #require(URL(string: "https://example.com/ask?text=x"))) == nil)
        #expect(ShareDeepLink.parse(try #require(URL(string: "anyrouter://ask?action=reply"))) == nil)
        #expect(ShareDeepLink.parse(try #require(URL(string: "anyrouter://ask?text=")))  == nil)
        let unknown = try #require(ShareDeepLink.parse(try #require(URL(string: "anyrouter://ask?text=hi&action=nope"))))
        #expect(unknown.action == .ask, "an unknown action falls back to a plain ask")
        let none = try #require(ShareDeepLink.parse(try #require(URL(string: "anyrouter://ask?text=hi"))))
        #expect(none.action == .ask)
    }

    @Test func everyActionNamesAShippedPreset() throws {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        for action in ShareAction.allCases {
            #expect(!action.title.isEmpty)
            if let id = action.presetID { #expect(items.contains { $0.id == id }, "\(action)") }
        }
        #expect(ShareAction.ask.presetID == nil)
    }

    @Test func theMessagesSayWhatToDoInstead() {
        #expect(ShareMessages.noAppGroup(hasFiles: true).contains("attach the file"))
        #expect(ShareMessages.noAppGroup(hasFiles: false).contains("paste"))
        #expect(!ShareMessages.saveFailed.isEmpty)
    }

    // MARK: Requests

    @Test func textAndLinkAreJoinedAndNothingIsNil() {
        #expect(ShareImportLogic.text(of: SharedPayload(text: " Look \n", url: "https://example.com")) == "Look\nhttps://example.com")
        #expect(ShareImportLogic.text(of: SharedPayload(url: "https://example.com")) == "https://example.com")
        #expect(ShareImportLogic.text(of: SharedPayload(text: "  ")) == nil)
        #expect(ShareImportLogic.text(of: SharedPayload()) == nil)
    }

    @Test func aPresetWithPickersAsksForItsChoicesOnlyWhenThereIsText() throws {
        let store = try presetStore()
        let reply = try #require(store.preset(id: "reply-to-this"))
        let summarize = try #require(store.preset(id: "summarize"))
        #expect(ShareImportLogic.request(text: "hi", preset: reply).asksForText)
        #expect(!ShareImportLogic.request(text: nil, preset: reply).asksForText)
        #expect(!ShareImportLogic.request(text: "hi", preset: summarize).asksForText)
        #expect(ShareImportLogic.request(text: "hi", preset: nil).presetID == nil)
    }

    @Test func aLinkBecomesARequestWithItsPreset() throws {
        let store = try presetStore()
        let url = try #require(ShareDeepLink.askURL(text: "Long email text", action: .fixEnglish))
        let request = try #require(ShareImportLogic.request(for: url, presets: store))
        #expect(request.text == "Long email text" && request.presetID == "fix-english" && !request.asksForText)
        #expect(ShareImportLogic.request(for: ShareDeepLink.shareURL, presets: store) == nil)
    }

    @Test func theNewestShareOpensAFreshChatAndOlderOnesAreDropped() throws {
        let store = try presetStore()
        let inbox = ShareInbox(root: tempFolder())
        let work = tempFolder().appending(path: "work")
        let mailbox = InboundChatMailbox()
        try save(inbox, text: "old", at: Date(timeIntervalSince1970: 1))
        try save(inbox, text: "Summary of this page", url: "https://example.com", files: [
            (SharedFile(filename: "doc.pdf", kind: .pdf), Data("pdf".utf8)),
            (SharedFile(filename: "scan.jpg", kind: .image), Data("img".utf8)),
        ], action: .summarize, at: Date(timeIntervalSince1970: 2))

        #expect(ShareImportLogic.pickUp(inbox: inbox, presets: store, mailbox: mailbox, workDirectory: work))
        let request = try #require(mailbox.take())
        #expect(request.text == "Summary of this page\nhttps://example.com")
        #expect(request.presetID == "summarize")
        #expect(request.files.map(\.lastPathComponent) == ["doc.pdf"])
        #expect(request.readsTextFrom.map(\.lastPathComponent) == ["scan.jpg"])
        #expect(try Data(contentsOf: request.files[0]) == Data("pdf".utf8), "the files moved with the request")
        #expect(inbox.pending().isEmpty, "the old share was dropped and the new one claimed")

        #expect(!ShareImportLogic.pickUp(inbox: inbox, presets: store, mailbox: mailbox, workDirectory: work))
        #expect(mailbox.take() == nil)
    }

    @Test func aShareThatCannotBeClaimedIsDroppedNotRetriedForever() throws {
        let store = try presetStore()
        let inbox = ShareInbox(root: tempFolder())
        let blocker = tempFolder().appending(path: "blocker")
        try Data("a file where a folder should be".utf8).write(to: blocker)
        let mailbox = InboundChatMailbox()
        try save(inbox, text: "hi")

        #expect(!ShareImportLogic.pickUp(inbox: inbox, presets: store, mailbox: mailbox, workDirectory: blocker.appending(path: "work")))
        #expect(mailbox.pending == nil)
        #expect(inbox.pending().isEmpty)
    }

    // MARK: Chat

    private func chat() async throws -> ChatViewModel {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["ok"]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        return ChatViewModel(thread: nil, context: context, registry: registry,
                             settings: AppSettings(defaults: testDefaults()), models: models,
                             attachments: AttachmentStore(root: tempFolder()))
    }

    @Test func aSharedPDFIsAttachedAndASharedPhotoIsRead() async throws {
        let vm = try await chat()
        let folder = tempFolder()
        let pdfURL = folder.appending(path: "report.pdf")
        try pdf(text: "Quarterly report").write(to: pdfURL)
        let photoURL = folder.appending(path: "receipt.png")
        let fixture = try #require(Bundle(for: ShareFixtureAnchor.self).url(forResource: "receipt", withExtension: "png"))
        try Data(contentsOf: fixture).write(to: photoURL)
        let unreadable = folder.appending(path: "gone.png")

        var request = InboundChat(text: "Summarize this", presetID: nil)
        request.files = [pdfURL]
        request.readsTextFrom = [photoURL, unreadable]
        _ = vm.start(request, preset: nil)

        #expect(await waitUntil { vm.pending.count == 1 && vm.scannedText != nil })
        #expect(vm.pending.first?.filename == "report.pdf")
        #expect(vm.scannedText?.text.contains("TOTAL") == true)
        #expect(vm.input == "Summarize this")
    }
}

private final class ShareFixtureAnchor {}
