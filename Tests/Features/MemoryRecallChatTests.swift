import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// Memory across chats as the model receives it (agent design E1, E8, E10).
@MainActor
struct MemoryRecallChatTests {
    @MainActor private struct Rig {
        let context: ModelContext
        let registry: EngineRegistry
        let models: ModelStore
        let settings: AppSettings
        let engine: ScriptedEngine
        var store: MemoryStore { MemoryStore(context: context) }

        func chat() -> ChatViewModel {
            ChatViewModel(thread: nil, context: context, registry: registry, settings: settings, models: models, isOnline: { true })
        }

        func send(_ text: String, in vm: ChatViewModel) async {
            vm.input = text
            await vm.send()?.value
        }

        var lastQuestion: String? { engine.messagesSeen.lastTexts.last }
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
        return Rig(context: context, registry: registry, models: models, settings: AppSettings(defaults: testDefaults()), engine: engine)
    }

    @Test func whatOneChatWasToldReachesTheNextChat() async throws {
        let r = try await rig()
        let first = r.chat()
        await r.send("Remember that I'm vegetarian", in: first)
        await r.send("Remember that my dog is called Mochi", in: first)
        #expect(first.messages.last?.memoryHits.isEmpty == true, "the question that saved it does not recall it")

        let next = r.chat()
        await r.send("What treats can Mochi eat?", in: next)
        #expect(r.engine.systemPromptsSeen.seen.last??.contains("I'm vegetarian") == true, "who the user is goes in every chat")
        #expect(r.lastQuestion == MemoryRecallLogic.heading + "\n- My dog is called Mochi\n\nWhat treats can Mochi eat?")
        #expect(next.messages.first?.content == "What treats can Mochi eat?", "the saved question stays as typed")
        let reply = try #require(next.messages.last)
        #expect(reply.memoryHits.map(\.text) == ["My dog is called Mochi"])
        let record = try #require(try r.store.all().first { $0.text == "My dog is called Mochi" })
        #expect(record.useCount == 1 && record.lastUsedAt != nil)
    }

    @Test func forgetRemovesTheItemFromMemoryAndFromTheNextRequest() async throws {
        let r = try await rig()
        try r.store.add("My dog is called Mochi", kind: .fact)
        let vm = r.chat()
        await r.send("Treats for Mochi?", in: vm)
        let hit = try #require(vm.messages.last?.memoryHits.first)
        try r.store.forget(hit.memoryID)
        try r.store.forget(hit.memoryID)
        #expect(try r.store.all().isEmpty)
        await r.send("More treats for Mochi?", in: vm)
        #expect(r.lastQuestion == "More treats for Mochi?")
        #expect(vm.messages.last?.memoryHits.isEmpty == true)
    }

    @Test func aCloudChatRecallsOnDeviceItemsOnlyWithTheSwitchOn() async throws {
        let r = try await rig(source: .anyrouter)
        try r.store.add("My dog is called Mochi", kind: .fact, origin: .extracted, scope: .deviceOnly)
        let vm = r.chat()
        await r.send("Treats for Mochi?", in: vm)
        #expect(r.lastQuestion == "Treats for Mochi?")
        r.settings.deviceMemoriesInCloudChats = true
        await r.send("Toys for Mochi?", in: vm)
        #expect(r.lastQuestion?.contains("My dog is called Mochi") == true)
    }

    @Test func noRecallWithMemoryOffForTheChat() async throws {
        let r = try await rig()
        try r.store.add("My dog is called Mochi", kind: .fact)
        let vm = r.chat()
        vm.setMemoryOff(true)
        await r.send("Treats for Mochi?", in: vm)
        #expect(r.lastQuestion == "Treats for Mochi?")
    }
}
