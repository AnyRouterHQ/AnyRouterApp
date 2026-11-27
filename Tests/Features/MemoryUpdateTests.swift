import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// "Remember that" in a message, the reply's "Memory updated" row, Undo and Edit (agent design 2.3, E1 save half).
@MainActor
struct MemoryUpdateTests {
    @MainActor private struct Rig {
        let vm: ChatViewModel
        let context: ModelContext
        let settings: AppSettings
        var store: MemoryStore { MemoryStore(context: context) }
        var reply: MessageRecord? { vm.messages.last { $0.role == .assistant } }

        func send(_ text: String) async {
            vm.input = text
            await vm.send()?.value
        }
    }

    private func rig(source: ModelSource = .apple) async throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let id = source == .anyrouter ? "anyrouter/test" : "apple/foundation"
        var engine = ScriptedEngine(source: source, models: [testModel(id: id, source: source)])
        engine.numberedReplies = true
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let settings = AppSettings(defaults: testDefaults())
        let vm = ChatViewModel(thread: nil, context: context, registry: registry, settings: settings, models: models, isOnline: { true })
        return Rig(vm: vm, context: context, settings: settings)
    }

    @Test func rememberThatSavesTheItemFromThisChatAndTheReplyShowsIt() async throws {
        let r = try await rig()
        await r.send("Remember that I'm vegetarian")
        let record = try #require(try r.store.all().first)
        #expect(record.text == "I'm vegetarian" && record.kind == .profile && record.origin == .askedInChat)
        #expect(record.scope == .deviceOnly, "said to a model on this device, so it stays off cloud models")
        #expect(record.sourceThreadID == r.vm.thread?.id)
        #expect(record.sourceMessageID == r.vm.messages.first?.id)
        #expect(r.reply?.content == "reply 1")
        #expect(r.reply?.memoryUpdates.map(\.outcome) == [.saved])
        #expect(r.reply?.memoryUpdates.first?.memoryID == record.id)
    }

    @Test func whatACloudChatSavesMayGoToEveryModel() async throws {
        let r = try await rig(source: .anyrouter)
        await r.send("Remember that I'm vegetarian")
        #expect(try r.store.all().map(\.scope) == [.everywhere])
    }

    @Test func automaticSavesWaitForTheirSwitchButAnAskDoesNot() async throws {
        let r = try await rig()
        r.settings.saveMemoriesAutomatically = false
        await r.send("My name is Lan.")
        #expect(try r.store.all().isEmpty)
        #expect(r.reply?.memoryUpdates.isEmpty == true)
        await r.send("Remember that I'm vegetarian")
        #expect(try r.store.all().map(\.text) == ["I'm vegetarian"])
    }

    @Test func nothingIsSavedWithMemoryOffForTheChatOrEverywhere() async throws {
        let r = try await rig()
        r.vm.setMemoryOff(true)
        await r.send("Remember that I'm vegetarian")
        r.vm.setMemoryOff(false)
        r.settings.useMemory = false
        await r.send("Remember that I'm vegan")
        #expect(try r.store.all().isEmpty)
    }

    @Test func undoDeletesTheItemAndTheRowSaysSo() async throws {
        let r = try await rig()
        await r.send("Remember that I'm vegetarian")
        let reply = try #require(r.reply)
        let update = try #require(reply.memoryUpdates.first)
        try r.store.undo(update, on: reply)
        #expect(try r.store.all().isEmpty)
        #expect(reply.memoryUpdates.map(\.outcome) == [.undone])
        #expect(reply.memoryUpdates.first?.memoryID == nil)
        try r.store.edit(try #require(reply.memoryUpdates.first), to: "I'm vegan", on: reply)
        #expect(try r.store.all().isEmpty, "an undone row has nothing left to edit")
    }

    @Test func editChangesTheItemAndTheRow() async throws {
        let r = try await rig()
        await r.send("Remember that I'm vegetarian")
        let reply = try #require(r.reply)
        try r.store.edit(try #require(reply.memoryUpdates.first), to: "I'm vegan", on: reply)
        #expect(try r.store.all().map(\.text) == ["I'm vegan"])
        #expect(reply.memoryUpdates.map(\.text) == ["I'm vegan"])
        #expect(reply.memoryUpdates.map(\.outcome) == [.saved])
    }

    @Test func aRepeatSaysItIsAlreadyInMemoryAndAFullListSaysWhy() async throws {
        let r = try await rig()
        await r.send("Remember that I'm vegetarian")
        await r.send("Remember that i'm VEGETARIAN")
        #expect(r.reply?.memoryUpdates.map(\.outcome) == [.alreadySaved])
        // "I'm vegetarian" is an About you item: it counts toward the 60 with the notes.
        for index in 0..<59 { try r.store.add("Note \(index)", kind: .note) }
        await r.send("From now on, answer briefly.")
        guard case .refused(let reason) = r.reply?.memoryUpdates.first?.outcome else {
            Issue.record("a full list refuses the save")
            return
        }
        #expect(reason.contains("is full"))
    }

    @Test func rememberOnSelectedReplyTextPinsANoteShownOnThatReply() async throws {
        let r = try await rig(source: .anyrouter)
        await r.send("hi")
        let reply = try #require(r.reply)
        try r.store.pin("Lan likes tram 28.", from: reply)
        let record = try #require(try r.store.all().first)
        #expect(record.kind == .note && record.origin == .askedInChat)
        #expect(record.scope == .everywhere && record.sourceMessageID == reply.id && record.sourceThreadID == r.vm.thread?.id)
        #expect(reply.memoryUpdates.map(\.outcome) == [.saved])
        try r.store.pin(String(repeating: "a", count: 300), from: reply)
        #expect(reply.memoryUpdates.count == 2)
        guard case .refused = reply.memoryUpdates.last?.outcome else {
            Issue.record("a selection that is too long says so on the row")
            return
        }
    }

    @Test func aPinFromAnOnDeviceReplyStaysOffCloudModels() async throws {
        let r = try await rig()
        await r.send("hi")
        try r.store.pin("Lan likes tram 28.", from: try #require(r.reply))
        #expect(try r.store.all().map(\.scope) == [.deviceOnly])
    }

    @Test func regenerateKeepsTheRowSoUndoStaysAtHand() async throws {
        let r = try await rig()
        await r.send("Remember that I'm vegetarian")
        let before = try #require(r.reply?.memoryUpdates)
        await r.vm.regenerate()?.value
        #expect(r.reply?.content == "reply 2")
        #expect(r.reply?.memoryUpdates == before)
    }
}
