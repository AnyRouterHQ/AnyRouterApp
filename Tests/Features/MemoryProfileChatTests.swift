import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// The always-on profile as the model receives it (agent design E2, E8 and E10 for the profile).
@MainActor
struct MemoryProfileChatTests {
    @MainActor private struct Rig {
        let context: ModelContext
        let registry: EngineRegistry
        let models: ModelStore
        let settings: AppSettings
        let engine: ScriptedEngine
        var store: MemoryStore { MemoryStore(context: context) }

        func chat(_ thread: ThreadRecord? = nil) -> ChatViewModel {
            ChatViewModel(thread: thread, context: context, registry: registry, settings: settings, models: models, isOnline: { true })
        }

        var prompts: [String?] { engine.systemPromptsSeen.seen }
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

    private func send(_ vm: ChatViewModel, _ text: String) async {
        vm.input = text
        await vm.send()?.value
    }

    @Test func theProfileIsTheSameOnEveryTurnAndAfterARelaunchThoughAMemoryWasSavedBetween() async throws {
        let r = try await rig()
        try r.store.add("Answer in Vietnamese.", kind: .preference)
        let vm = r.chat()
        await send(vm, "hi")
        try r.store.add("My name is Lan.", kind: .profile)
        await send(vm, "again")
        await send(r.chat(vm.thread), "after a relaunch")
        let first = try #require(r.prompts.first ?? nil)
        #expect(first.contains("- Answer in Vietnamese."))
        #expect(!first.contains("Lan"), "a memory saved during the chat is in its messages, not its prompt")
        #expect(r.prompts == [first, first, first])
    }

    @Test func dontUseMemoryInThisChatLeavesTheProfileOutAndIsKeptWithTheChat() async throws {
        let r = try await rig()
        try r.store.add("Answer in Vietnamese.", kind: .preference)
        let vm = r.chat()
        vm.setMemoryOff(true)
        await send(vm, "hi")
        #expect(vm.thread?.memoryOff == true)
        #expect(r.chat(vm.thread).memoryOff)
        vm.setMemoryOff(false)
        await send(vm, "again")
        #expect(r.prompts.count == 2)
        #expect(r.prompts[0] == nil)
        #expect(r.prompts[1]?.contains("Answer in Vietnamese.") == true)
    }

    @Test func turningMemoryOffInSettingsLeavesTheProfileOutOfEveryChat() async throws {
        let r = try await rig()
        try r.store.add("Answer in Vietnamese.", kind: .preference)
        r.settings.useMemory = false
        await send(r.chat(), "hi")
        #expect(r.prompts == [nil])
    }

    @Test func aCloudModelGetsOnDeviceMemoriesOnlyWithTheSwitchOn() async throws {
        let r = try await rig(source: .anyrouter)
        try r.store.add("I take insulin.", kind: .profile, origin: .extracted, scope: .deviceOnly)
        try r.store.add("Answer in Vietnamese.", kind: .preference)
        let vm = r.chat()
        await send(vm, "hi")
        r.settings.deviceMemoriesInCloudChats = true
        await send(vm, "again")
        #expect(r.prompts.count == 2)
        #expect(r.prompts[0]?.contains("Answer in Vietnamese.") == true)
        #expect(r.prompts[0]?.contains("insulin") == false)
        #expect(r.prompts[1]?.contains("insulin") == true)
    }

    @Test func aDeletedMemoryLeavesTheNextRequest() async throws {
        let r = try await rig()
        let record = try r.store.add("Answer in Vietnamese.", kind: .preference)
        let vm = r.chat()
        await send(vm, "hi")
        try r.store.delete(record)
        await send(vm, "again")
        #expect(r.prompts.count == 2)
        #expect(r.prompts[0] != nil)
        #expect(r.prompts[1] == nil)
    }
}
