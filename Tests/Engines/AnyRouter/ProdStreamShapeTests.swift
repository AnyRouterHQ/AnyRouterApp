import Foundation
import Testing
@testable import AnyRouter

/// The stream shape production sends today: an extra top-level "p" field, no standard usage chunk,
/// token counts only inside anyrouter_metadata.
struct ProdStreamShapeTests {
    private let body = """
        data: {"p":"abcdefghijklmnopqrstuvwxyz0123456789","id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":"4","role":"assistant"},"finish_reason":null}],"created":1795672709,"model":"nvidia/nemotron-3.5-bolt-e4b","object":"chat.completion.chunk"}

        data: {"p":"abcdefghijklmnopqrstuvwxyz0123456789","id":"chatcmpl-1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"created":1795672709,"model":"nvidia/nemotron-3.5-bolt-e4b","object":"chat.completion.chunk","anyrouter_metadata":{"usage":{"inputTokens":21,"outputTokens":2,"totalTokens":23},"finishReason":"stop"}}

        data: [DONE]


        """

    @Test func unknownTopLevelFieldsAreIgnoredAndMetadataUsageFillsTheGap() async throws {
        let api = StubbedAPI { _ in StubRegistry.Reply(body: Data(body.utf8)) }
        let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
        var texts: [String] = []
        var usage: [ChatDelta] = []
        for try await delta in engine.stream(model: testModel(id: "anyrouter/anyrouter/auto", source: .anyrouter),
                                             messages: [ChatMessage(role: .user, content: "What is 2+2? Answer with one number.")],
                                             params: GenerationParams()) {
            switch delta {
            case .text(let piece): texts.append(piece)
            case .usage: usage.append(delta)
            default: break
            }
        }
        #expect(texts == ["4"])
        #expect(usage == [.usage(prompt: 21, completion: 2)])
    }
}
