import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// Switching models in the middle of a conversation, across engines (Apple, then AnyRouter).
@MainActor
struct ModelSwitchTests {
    private struct Rig {
        let vm: ChatViewModel
        let apple: ScriptedEngine
        let cloud: ScriptedEngine
        let context: ModelContext
        let registry: EngineRegistry
        let models: ModelStore

        func reopen() -> ChatViewModel {
            ChatViewModel(thread: vm.thread, context: context, registry: registry,
                          settings: AppSettings(defaults: testDefaults()), models: models)
        }
    }

    private let appleModel = testModel(id: "apple/foundation", source: .apple)
    private let cloudA = cloudModel("openai/gpt-5", name: "GPT-5")

    private func rig() async throws -> Rig {
        var apple = ScriptedEngine(source: .apple, models: [testModel(id: "apple/foundation", source: .apple)])
        apple.chunks = ["from apple"]
        var cloud = ScriptedEngine(source: .anyrouter, models: [cloudModel("openai/gpt-5", name: "GPT-5")])
        cloud.chunks = ["from cloud"]
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(apple)
        registry.register(cloud)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(thread: nil, context: context, registry: registry,
                               settings: AppSettings(defaults: testDefaults()), models: models)
        return Rig(vm: vm, apple: apple, cloud: cloud, context: context, registry: registry, models: models)
    }

    @Test func pickingAnotherModelMidConversationSendsTheNextMessageThere() async throws {
        let r = try await rig()
        r.vm.choose(appleModel)
        r.vm.input = "first"
        await r.vm.send()?.value
        #expect(r.vm.messages.last?.content == "from apple")

        r.vm.choose(cloudA) // from the pill or the sheet
        #expect(r.vm.model?.id == cloudA.id) // the pill shows it at once
        r.vm.input = "second"
        await r.vm.send()?.value

        #expect(r.apple.usedModels.values == [appleModel.id])
        #expect(r.cloud.usedModels.values == [cloudA.id])
        #expect(r.vm.messages.map(\.content) == ["first", "from apple", "second", "from cloud"])
        #expect(r.vm.thread?.modelID == cloudA.id)
        #expect(r.reopen().model?.id == cloudA.id) // reopening the thread shows the new model
    }

    @Test func eachReplyRemembersItsModelAndTheSwitchIsAnnounced() async throws {
        let r = try await rig()
        r.vm.choose(appleModel)
        r.vm.input = "one"
        await r.vm.send()?.value
        r.vm.choose(cloudA)
        r.vm.input = "two"
        await r.vm.send()?.value
        r.vm.input = "three"
        await r.vm.send()?.value

        let replies = r.vm.messages.filter { $0.role == .assistant }
        #expect(replies.map(\.modelID) == [appleModel.id, cloudA.id, cloudA.id])
        let notes = SwitchNotes.make(r.vm.messages)
        #expect(notes.count == 1)
        #expect(notes[replies[1].id] == "Switched to GPT-5")
    }

    @Test func noNoteWithoutASwitchOrForOldRepliesWithoutAModelId() {
        let a = MessageRecord(role: .assistant, content: "x", modelName: "A", modelID: "a")
        let b = MessageRecord(role: .assistant, content: "y", modelName: "A", modelID: "a")
        let legacy = MessageRecord(role: .assistant, content: "z")
        #expect(SwitchNotes.make([a, b, legacy]).isEmpty)
    }

    @Test func switchingBackAnnouncesAgain() {
        let a1 = MessageRecord(role: .assistant, content: "1", modelName: "A", modelID: "a")
        let b = MessageRecord(role: .assistant, content: "2", modelName: "B", modelID: "b")
        let a2 = MessageRecord(role: .assistant, content: "3", modelName: "A", modelID: "a")
        let notes = SwitchNotes.make([a1, b, a2])
        #expect(notes[b.id] == "Switched to B")
        #expect(notes[a2.id] == "Switched to A")
        #expect(notes[a1.id] == nil)
    }
}
