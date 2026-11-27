import Foundation
import SwiftData
import Testing
@testable import AnyRouter

struct EscalationLogicTests {
    private func model(_ id: String, _ source: ModelSource, installed: Bool = true) -> ModelDescriptor {
        ModelDescriptor(id: id, source: source, displayName: id, contextLength: nil, capabilities: ["chat"], sizeBytes: nil, isInstalled: installed)
    }

    @Test func theRouterIsPickedWhenTheAccountHasItElseTheFirstCloudModel() {
        let apple = model("apple/foundation", .apple)
        let gpt = model("anyrouter/openai/gpt-5", .anyrouter)
        let router = model(ModelDescriptor.autoRouterID, .anyrouter)
        #expect(EscalationLogic.cloudModel(in: [apple, gpt, router])?.id == ModelDescriptor.autoRouterID)
        #expect(EscalationLogic.cloudModel(in: [apple, gpt])?.id == gpt.id)
        #expect(EscalationLogic.cloudModel(in: [apple, model("anyrouter/x", .anyrouter, installed: false)]) == nil)
        #expect(EscalationLogic.confirmTitle(for: gpt) == "Ask \(gpt.shortName)")
    }

    @Test func onlyARepliesFromThisDeviceAreHandedToTheCloud() {
        #expect(EscalationLogic.isDeviceReply(modelID: "apple/foundation"))
        #expect(EscalationLogic.isDeviceReply(modelID: "gguf/x/Qwen/q4.gguf"))
        #expect(!EscalationLogic.isDeviceReply(modelID: "anyrouter/auto"))
        #expect(!EscalationLogic.isDeviceReply(modelID: nil))
        #expect(EscalationLogic.noticeMessage.contains("AnyRouter"))
    }
}

/// X1: a device reply that failed is asked again of a cloud model, only when the user says so.
@MainActor
struct EscalationChatTests {
    @Test func askACloudModelReplacesTheDeviceReplyWithTheCloudOne() async throws {
        var device = ScriptedEngine(source: .apple, models: [testModel()])
        device.failure = "Exceeded the context window size."
        let cloud = ScriptedEngine(source: .anyrouter, models: [testModel(id: "anyrouter/openai/gpt-5", source: .anyrouter)], chunks: ["From the cloud."])
        let registry = EngineRegistry()
        registry.register(device)
        registry.register(cloud)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(
            thread: nil, context: ModelContext(try ModelContainer.anyRouter(inMemory: true)), registry: registry,
            settings: AppSettings(defaults: testDefaults()), models: models)
        vm.choose(try #require(models.models.first { $0.source == .apple }))
        vm.input = "A very long question"
        await vm.send()?.value
        #expect(vm.messages.last?.failure?.kind == .contextTooLong)
        #expect(vm.escalationModel?.id == "anyrouter/openai/gpt-5")
        await vm.askCloudModel()?.value
        #expect(vm.messages.map(\.role) == [.user, .assistant])
        #expect(vm.messages.last?.content == "From the cloud.")
        #expect(vm.messages.last?.modelID == "anyrouter/openai/gpt-5")
        #expect(vm.model?.source == .anyrouter, "the chat goes on with the cloud model")
    }

    @Test func withoutACloudModelThereIsNothingToAsk() async throws {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(source: .apple, models: [testModel()]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(
            thread: nil, context: ModelContext(try ModelContainer.anyRouter(inMemory: true)), registry: registry,
            settings: AppSettings(defaults: testDefaults()), models: models)
        #expect(vm.askCloudModel() == nil)
    }
}
