import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// A chat's summary in memory when it loses focus (agent design 2.3, unit M6).
@MainActor
struct ChatSummaryChatTests {
    @MainActor private struct Rig {
        let vm: ChatViewModel
        let context: ModelContext
        let settings: AppSettings
        var summaries: [MemoryRecord] { MemoryStore(context: context).items.filter { $0.kind == .chatSummary } }

        func send(_ count: Int) async {
            for index in 0..<count {
                vm.input = "Question \(index)"
                await vm.send()?.value
            }
        }
    }

    private func rig() async throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        var engine = ScriptedEngine()
        engine.numberedReplies = true
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let settings = AppSettings(defaults: testDefaults())
        let vm = ChatViewModel(thread: nil, context: context, registry: registry, settings: settings, models: models)
        return Rig(vm: vm, context: context, settings: settings)
    }

    @Test func leavingALongChatKeepsOneSummaryThatOnlyANewMessageReplaces() async throws {
        let r = try await rig()
        await r.send(3)
        await r.vm.summarizeForMemory()?.value
        let summary = try #require(r.summaries.first)
        #expect(summary.text == "reply 4", "the fourth request is the summary")
        #expect(summary.sourceThreadID == r.vm.thread?.id && summary.scope == .deviceOnly && summary.origin == .extracted)
        #expect(r.vm.summarizeForMemory() == nil, "nothing changed since")
        await r.send(1)
        await r.vm.summarizeForMemory()?.value
        #expect(r.summaries.map(\.text) == ["reply 6"])
    }

    @Test func aShortenedChatUsesItsCompactionSummary() async throws {
        let r = try await rig()
        await r.send(3)
        let thread = try #require(r.vm.thread)
        thread.compactions = [Compaction(lastMessageID: r.vm.messages[1].id, summary: "They planned a trip.", droppedCount: 2, createdAt: Date())]
        #expect(r.vm.summarizeForMemory() == nil)
        #expect(r.summaries.map(\.text) == ["They planned a trip."])
    }

    @Test func aShortChatOrMemoryOffWritesNothing() async throws {
        let r = try await rig()
        await r.send(1)
        #expect(r.vm.summarizeForMemory() == nil)
        await r.send(2)
        r.settings.useMemory = false
        #expect(r.vm.summarizeForMemory() == nil)
        #expect(r.summaries.isEmpty)
    }
}
