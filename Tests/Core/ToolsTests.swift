import XCTest

@testable import AnyRouter

final class ToolsTests: XCTestCase {
    /// Engine that only knows the plain `stream`, like the on-device engines today.
    private struct PlainEngine: ChatEngine {
        var source: ModelSource { .gguf }
        func availableModels() async throws -> [ModelDescriptor] { [] }
        func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
            -> AsyncThrowingStream<ChatDelta, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.text("plain"))
                continuation.yield(.done(finishReason: "stop"))
                continuation.finish()
            }
        }
    }

    private struct NoTools: ToolHost {
        var specs: [ToolSpec] { [] }
        func execute(_ call: ToolCall) async -> ToolResult {
            ToolResult(callID: call.id, name: call.name, text: "", isError: false)
        }
    }

    func testEngineWithoutToolSupportStreamsPlainTextWhenGivenAHost() async throws {
        let model = ModelDescriptor(
            id: "gguf/x", source: .gguf, displayName: "x", contextLength: nil,
            capabilities: ["chat"], sizeBytes: nil, isInstalled: true
        )
        var deltas: [ChatDelta] = []
        let stream = PlainEngine().stream(model: model, messages: [], params: GenerationParams(), tools: NoTools())
        for try await delta in stream { deltas.append(delta) }
        XCTAssertEqual(deltas, [.text("plain"), .done(finishReason: "stop")])
    }

    func testToolStepRoundTripsAndIsIdentifiedByItsCall() throws {
        let call = ToolCall(id: "call_1", name: "web_search", argumentsJSON: #"{"q":"swift"}"#)
        let result = ToolResult(callID: "call_1", name: "web_search", text: "3 hits", isError: false)
        let step = ToolStep(call: call, result: result)
        XCTAssertEqual(step.id, "call_1")
        let decoded = try JSONDecoder().decode(ToolStep.self, from: JSONEncoder().encode(step))
        XCTAssertEqual(decoded, step)

        let spec = ToolSpec(name: "web_search", title: nil, description: "Search", schema: "{}", isReadOnly: true)
        XCTAssertEqual(spec.id, "web_search")
    }
}
