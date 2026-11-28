import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// A cloud chat offers the skills the user owns and switched on, next to the bundled ones (agent design 4.2, unit K2).
@MainActor
struct SkillChatTests {
    private final class ToolBox {
        var tools: [any BuiltInTool] = []
    }

    private func send(source: ModelSource, in context: ModelContext) async throws -> (prompt: String?, tools: [any BuiltInTool]) {
        let id = source == .anyrouter ? "anyrouter/test" : "apple/foundation"
        var model = testModel(id: id, source: source)
        model.capabilities.insert("tools")
        let engine = ScriptedEngine(source: source, models: [model], chunks: ["ok"])
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let box = ToolBox()
        let vm = ChatViewModel(
            thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models,
            toolHost: { toolContext in
                box.tools = toolContext.memoryTools
                return AgentToolHost(builtIns: toolContext.memoryTools, search: nil, mcp: nil)
            })
        vm.input = "hi"
        await vm.send()?.value
        return (engine.systemPromptsSeen.seen.first ?? nil, box.tools)
    }

    @Test func aCloudChatListsAndReadsAnEnabledStoredSkillAndNeverADisabledOne() async throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let store = SkillStore(context: context)
        try store.add(SkillDraft(name: "bill-splitter", description: "Split a bill between friends.", body: "1. Ask who paid."), source: .imported)
        let off = try store.add(SkillDraft(name: "old-habit", description: "Not wanted any more.", body: "1. Nothing."), source: .hub)
        try store.setEnabled(off, false)

        let (prompt, tools) = try await send(source: .anyrouter, in: context)
        let text = try #require(prompt)
        #expect(text.contains("- bill-splitter: Split a bill between friends."))
        #expect(text.contains("- trip-planner:"), "the bundled skills stay")
        #expect(!text.contains("old-habit") && !text.contains("1. Ask who paid."), "a switched-off skill and every body stay out of the prompt")

        let read = try #require(tools.first { $0.name == SkillLogic.readSkillName })
        let body = try await read.run(.object(["name": .string("bill-splitter")]))
        #expect(body.contains("1. Ask who paid.") && body.contains("(imported)") && body.contains("cannot allow any tool"))
        await #expect(throws: BuiltInToolError.self) { try await read.run(.object(["name": .string("old-habit")])) }
    }

    @Test func aChatOnTheDeviceGetsNoStoredSkill() async throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        try SkillStore(context: context).add(SkillDraft(name: "bill-splitter", description: "Split a bill.", body: "1. Ask."), source: .imported)
        let (prompt, tools) = try await send(source: .apple, in: context)
        #expect(prompt?.contains("bill-splitter") != true)
        #expect(tools.isEmpty)
    }
}
