import Foundation
import Testing
@testable import AnyRouter

/// Servers send what a model thinks as `reasoning_content` or `reasoning` next to `content`.
struct ReasoningStreamTests {
    private func decode(_ payloads: [String]) throws -> [ChatDelta] {
        var decoder = ChatChunkDecoder()
        return try payloads.flatMap { try decoder.decode($0) }
    }

    @Test func bothSpellingsBecomeReasoningDeltas() throws {
        let deltas = try decode([
            #"{"choices":[{"delta":{"reasoning_content":"one "}}]}"#,
            #"{"choices":[{"delta":{"reasoning":"two"}}]}"#,
        ])
        #expect(deltas == [.reasoning("one "), .reasoning("two")])
    }

    @Test func reasoningComesBeforeTheTextOfTheSameChunk() throws {
        let deltas = try decode([#"{"choices":[{"delta":{"reasoning_content":"r","content":"t"}}]}"#])
        #expect(deltas == [.reasoning("r"), .text("t")])
    }

    @Test func emptyOrMissingReasoningAddsNothing() throws {
        let deltas = try decode([
            #"{"choices":[{"delta":{"reasoning_content":"","content":"t"}}]}"#,
            #"{"choices":[{"delta":{"reasoning":null}}]}"#,
        ])
        #expect(deltas == [.text("t")])
    }

    @Test func theEngineStreamsReasoningThroughItsToolLoop() async throws {
        let body = """
            data: {"choices":[{"delta":{"reasoning_content":"Think. "}}]}

            data: {"choices":[{"delta":{"content":"Hi"}}]}

            data: [DONE]


            """
        let api = StubbedAPI { _ in StubRegistry.Reply(body: Data(body.utf8)) }
        let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
        var seen: [ChatDelta] = []
        for try await delta in engine.stream(model: testModel(id: "anyrouter/anyrouter/auto", source: .anyrouter),
                                             messages: [ChatMessage(role: .user, content: "Hello")],
                                             params: GenerationParams()) {
            if case .reasoning = delta { seen.append(delta) }
            if case .text = delta { seen.append(delta) }
        }
        #expect(seen == [.reasoning("Think. "), .text("Hi")])
    }
}
