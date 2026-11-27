import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// What the chat keeps when a model thinks before it answers: in reasoning deltas, or inline as <think>.
@MainActor
struct ReasoningChatTests {
    private func reply(_ engine: ScriptedEngine) async throws -> MessageRecord {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let vm = ChatViewModel(thread: nil, context: context, registry: registry,
                               settings: AppSettings(defaults: testDefaults()), models: models)
        vm.input = "Why is the sky blue?"
        await vm.send()?.value
        return try #require(vm.messages.last)
    }

    @Test func reasoningDeltasAreKeptApartFromTheAnswerWithTheirTime() async throws {
        let message = try await reply(ScriptedEngine(deltas: [.reasoning("Let me "), .reasoning("think."), .text("Rayleigh scattering.")]))
        #expect(message.content == "Rayleigh scattering.")
        #expect(message.reasoning?.text == "Let me think.")
        #expect(message.reasoning?.durationMs != nil, "the answer started, so the thinking has an end")
    }

    @Test func aThinkBlockInTheTextBecomesReasoning() async throws {
        let message = try await reply(ScriptedEngine(chunks: ["<think>pl", "an</think>", "\nAnswer"]))
        #expect(message.content == "Answer")
        #expect(message.reasoning?.text == "plan")
    }

    @Test func aReplyOfOnlyThoughtsIsKept() async throws {
        let message = try await reply(ScriptedEngine(deltas: [.reasoning("hmm")]))
        #expect(message.content.isEmpty)
        #expect(message.reasoning == ReasoningTrace(text: "hmm", durationMs: message.reasoning?.durationMs))
        #expect(message.reasoning?.durationMs != nil, "the stream ended, so the thinking ended")
    }

    @Test func aBlockThatNeverClosedStaysReasoning() async throws {
        let message = try await reply(ScriptedEngine(chunks: ["<think>abc</thi"]))
        #expect(message.content.isEmpty)
        #expect(message.reasoning?.text == "abc</thi")
    }

    @Test func aReplyThatEndsInsideAnOpeningTagShowsWhatItWrote() async throws {
        let message = try await reply(ScriptedEngine(chunks: ["<th"]))
        #expect(message.content == "<th")
        #expect(message.reasoning == nil)
    }

    @Test func aToolCallEndsTheThinkingBeforeTheAnswer() async throws {
        let call = ToolCall(id: "c1", name: "calculator", argumentsJSON: #"{"expression":"1+1"}"#)
        let message = try await reply(ScriptedEngine(deltas: [
            .reasoning("I should calculate."), .toolCall(call),
            .toolResult(ToolResult(callID: "c1", name: "calculator", text: "2", isError: false)), .text("It is 2."),
        ]))
        #expect(message.reasoning?.text == "I should calculate.")
        #expect(message.reasoning?.durationMs != nil)
        #expect(message.toolSteps.count == 1)
        #expect(message.content == "It is 2.")
    }
}
