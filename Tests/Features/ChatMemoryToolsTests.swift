import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// The cloud model's `memory` and `search_chats` tools and their scope rules (agent design 2.4, 2.6, E8).
@MainActor
struct ChatMemoryToolsTests {
    @MainActor private struct Rig {
        let context: ModelContext
        let settings: AppSettings
        let thread: ThreadRecord
        let reply: MessageRecord
        var store: MemoryStore { MemoryStore(context: context) }
        var tools: ChatMemoryTools { ChatMemoryTools(context: context, thread: thread, reply: reply, settings: settings) }

        func memory(_ fields: [String: JSONValue]) throws -> String { try tools.memory(.object(fields)) }
        func searchChats(_ query: String) throws -> String { try tools.searchChats(.object(["query": .string(query)])) }

        @discardableResult
        func chat(_ title: String, question: String, replyFrom modelID: String) -> ThreadRecord {
            let other = ThreadRecord(title: title)
            context.insert(other)
            let asked = MessageRecord(role: .user, content: question)
            let answered = MessageRecord(role: .assistant, content: "Sure.", modelID: modelID)
            context.insert(asked)
            context.insert(answered)
            asked.thread = other
            answered.thread = other
            return other
        }
    }

    private func rig() throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord(title: "Now")
        let reply = MessageRecord(role: .assistant, content: "", modelID: "anyrouter/auto")
        context.insert(thread)
        context.insert(reply)
        reply.thread = thread
        return Rig(context: context, settings: AppSettings(defaults: testDefaults()), thread: thread, reply: reply)
    }

    @Test func addSavesForEveryModelAndShowsARowWithUndo() throws {
        let r = try rig()
        let answer = try r.memory(["action": .string("add"), "text": .string("Prefers metric units."), "kind": .string("preference")])
        #expect(answer.hasPrefix("Saved."))
        let record = try #require(try r.store.all().first)
        #expect(record.kind == .preference && record.origin == .modelTool && record.scope == .everywhere)
        #expect(record.sourceThreadID == r.thread.id && record.sourceMessageID == r.reply.id)
        #expect(r.reply.memoryUpdates.map(\.outcome) == [.saved])
        #expect(try r.memory(["action": .string("add"), "text": .string("prefers METRIC units.")]) == "Already saved.")
    }

    @Test func withAutomaticSavingOffTheModelCannotAdd() throws {
        let r = try rig()
        r.settings.saveMemoriesAutomatically = false
        #expect(throws: BuiltInToolError.self) { try r.memory(["action": .string("add"), "text": .string("Likes tea.")]) }
        #expect(try r.store.all().isEmpty)
    }

    @Test func searchSeesOnDeviceItemsOnlyWithTheSwitchOn() throws {
        let r = try rig()
        try r.store.add("My dog is called Mochi", kind: .fact, origin: .extracted, scope: .deviceOnly)
        try r.store.add("Mochi eats carrots", kind: .fact)
        try r.store.add("Summary of an old chat about Mochi", kind: .chatSummary)
        let hidden = try r.memory(["action": .string("search"), "query": .string("Mochi")])
        #expect(hidden.contains("Mochi eats carrots") && !hidden.contains("called Mochi") && !hidden.contains("Summary"))
        r.settings.deviceMemoriesInCloudChats = true
        #expect(try r.memory(["action": .string("search"), "query": .string("Mochi")]).contains("called Mochi"))
        let newest = try r.memory(["action": .string("search")])
        #expect(newest.hasPrefix("- [") && newest.contains("Mochi eats carrots"))
    }

    @Test func removeDeletesTheItemAndUndoSavesItAgainAsItWas() throws {
        let r = try rig()
        let record = try r.store.add("Mochi eats carrots", kind: .fact)
        #expect(throws: BuiltInToolError.self) { try r.memory(["action": .string("remove"), "id": .string(UUID().uuidString)]) }
        #expect(try r.memory(["action": .string("remove"), "id": .string(record.id.uuidString)]).hasPrefix("Removed."))
        #expect(try r.store.all().isEmpty)
        let update = try #require(r.reply.memoryUpdates.first)
        #expect(update.outcome == .removed)
        try r.store.undo(update, on: r.reply)
        let restored = try #require(try r.store.all().first)
        #expect(restored.text == "Mochi eats carrots" && restored.kind == .fact && restored.scope == .everywhere)
        #expect(r.reply.memoryUpdates.map(\.outcome) == [.undone])
    }

    @Test func searchChatsFindsOtherCloudChatsAndOnDeviceOnesOnlyWithTheSwitch() throws {
        let r = try rig()
        r.chat("Trip to Da Lat", question: "Plan three days in Da Lat", replyFrom: "anyrouter/auto")
        r.chat("Private trip", question: "Da Lat hotels near the lake", replyFrom: "apple/foundation")
        let question = MessageRecord(role: .user, content: "Da Lat again")
        r.context.insert(question)
        question.thread = r.thread

        let found = try r.searchChats("Da Lat")
        #expect(found.contains("## Trip to Da Lat") && found.contains("Message: Plan three days in Da Lat"))
        #expect(!found.contains("Private trip"), "an on-device chat stays off cloud models")
        #expect(!found.contains("Da Lat again"), "the chat the model is in is not searched")
        r.settings.deviceMemoriesInCloudChats = true
        #expect(try r.searchChats("Da Lat").contains("Private trip"))
        #expect(try r.searchChats("nothing like this") == "No earlier chat matches.")
        #expect(throws: BuiltInToolError.self) { try r.tools.searchChats(.object([:])) }
    }

    @Test func aFoundChatCarriesItsSummary() throws {
        let r = try rig()
        let other = r.chat("Trip to Da Lat", question: "Plan three days in Da Lat", replyFrom: "anyrouter/auto")
        try r.store.add("Planned three days by bus.", kind: .chatSummary, sourceThreadID: other.id)
        #expect(try r.searchChats("Da Lat").contains("Summary: Planned three days by bus."))
    }

    @Test func aCloudChatGetsTheMemoryToolsAndAnOnDeviceChatDoesNot() async throws {
        for source in [ModelSource.anyrouter, .apple] {
            let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
            let id = source == .anyrouter ? "anyrouter/test" : "apple/foundation"
            var model = testModel(id: id, source: source)
            model.capabilities.insert("tools")
            let engine = ScriptedEngine(source: source, models: [model], chunks: ["ok"])
            let registry = EngineRegistry()
            registry.register(engine)
            let models = ModelStore(registry: registry, defaults: testDefaults())
            await models.refresh()
            let vm = ChatViewModel(
                thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models,
                toolHost: { context in context.memoryTools.isEmpty ? nil : AgentToolHost(builtIns: context.memoryTools, search: nil, mcp: nil) })
            vm.input = "hi"
            await vm.send()?.value
            let expected: [String]? = source == .anyrouter ? ["memory", "search_chats"] : nil
            #expect(engine.toolsSeen.seen == [expected])
        }
    }
}
