import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// A reply streaming in one window is live for every window of the app (the G1 two-window case on iPad).
@MainActor
struct LiveRepliesTests {
    @Test func aReplyIsLiveFromItsStartUntilItEnds() async throws {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: ["partial"], hangs: true))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let vm = ChatViewModel(thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models)
        vm.input = "hi"
        let task = try #require(vm.send())
        let reply = try #require(vm.messages.last)
        #expect(LiveReplies.shared.ids.contains(reply.id))
        let otherWindow = ChatViewModel(thread: vm.thread, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models)
        #expect(!otherWindow.isStreaming, "the other window's chat is idle, yet the reply is live")
        vm.stop()
        await task.value
        #expect(!LiveReplies.shared.ids.contains(reply.id))
    }
}
