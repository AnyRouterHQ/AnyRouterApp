import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// A chat on this device has no read_skill: one skill that matches the question goes in front of it for that request
/// only (agent design 4.2, unit K1).
@MainActor
struct SkillDeviceChatTests {
    private struct Rig {
        let context: ModelContext
        let engine: ScriptedEngine
        let chat: ChatViewModel

        func send(_ text: String) async {
            chat.input = text
            await chat.send()?.value
        }

        var lastQuestion: String? { engine.messagesSeen.lastTexts.last }
    }

    private func rig(source: ModelSource, id: String) async throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let engine = ScriptedEngine(source: source, models: [testModel(id: id, source: source)], chunks: ["ok"])
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let chat = ChatViewModel(
            thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models)
        return Rig(context: context, engine: engine, chat: chat)
    }

    private let steps = SkillLogic.guidance(SkillLogic.bundled[0])

    @Test(arguments: [(ModelSource.apple, "apple/foundation"), (.gguf, "gguf/test"), (.mlx, "mlx/test")])
    func aMatchingQuestionGetsTheSkillsStepsAndAnOrdinaryOneDoesNot(source: ModelSource, id: String) async throws {
        let r = try await rig(source: source, id: id)
        await r.send("Hello")
        #expect(r.lastQuestion == "Hello")
        await r.send("Plan a trip to Da Lat")
        #expect(r.lastQuestion == steps + "\n\nPlan a trip to Da Lat")
        #expect(r.chat.messages.first { $0.content.contains("Da Lat") }?.content == "Plan a trip to Da Lat", "the saved question stays as typed")
        #expect(r.engine.systemPromptsSeen.seen.last??.contains("trip-planner") != true, "the steps are not in the system message")
        await r.send("What is the capital of France?")
        #expect(r.lastQuestion == "What is the capital of France?")
    }

    @Test func aCloudChatKeepsTheIndexInTheSystemMessageNotTheSteps() async throws {
        let r = try await rig(source: .anyrouter, id: "anyrouter/test")
        await r.send("Plan a trip to Da Lat")
        #expect(r.lastQuestion == "Plan a trip to Da Lat")
    }

    @Test func withToolsSwitchedOffTheChatIsPlain() async throws {
        let r = try await rig(source: .apple, id: "apple/foundation")
        r.chat.setToolsEnabled(false)
        await r.send("Plan a trip to Da Lat")
        #expect(r.lastQuestion == "Plan a trip to Da Lat")
    }

    @Test func aStoredSkillMatchesWhenOnAndFitsAndNeverWhenOffOrTooLong() async throws {
        let r = try await rig(source: .apple, id: "apple/foundation")
        let store = SkillStore(context: r.context)
        try store.add(SkillDraft(name: "bill-splitter", description: "Split a bill between friends.", body: "1. Ask who paid."), source: .imported)
        let off = try store.add(SkillDraft(name: "tip-maker", description: "Work out a tip for a meal.", body: "1. Ask the total."), source: .hub)
        try store.setEnabled(off, false)
        try store.add(
            SkillDraft(name: "long-guide", description: "Write a poem about the sea.", body: String(repeating: "step ", count: 900)), source: .imported)

        await r.send("Split the bill between friends")
        #expect(r.lastQuestion?.contains("1. Ask who paid.") == true && r.lastQuestion?.hasSuffix("Split the bill between friends") == true)
        await r.send("Work out a tip for the meal")
        #expect(r.lastQuestion == "Work out a tip for the meal", "a switched-off skill is not used")
        await r.send("Write a poem about the sea")
        #expect(r.lastQuestion == "Write a poem about the sea", "a skill too long for the budget is not used")
    }
}
