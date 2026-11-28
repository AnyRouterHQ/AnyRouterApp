import Foundation
import Testing
@testable import AnyRouter

/// AnyRouter as a step of the app's tool loop, on a model whose window is known.
struct AnyRouterStepTests {
    private final class Bodies: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [[String: Any]] = []
        func add(_ request: URLRequest) {
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var collected = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    collected.append(buffer, count: count)
                }
                data = collected
            }
            let body = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
            lock.withLock { all.append(body) }
        }
        var list: [[String: Any]] { lock.withLock { all } }

        func toolMessages(_ index: Int) -> [String] {
            ((list[index]["messages"] as? [[String: Any]]) ?? []).filter { $0["role"] as? String == "tool" }.compactMap { $0["content"] as? String }
        }
    }

    /// Every page is 30,000 characters, about 10,000 tokens.
    private struct Pages: ToolHost {
        let specs = [ToolSpec(name: "page", title: nil, description: "Read a page", inputSchemaJSON: "{}", isReadOnly: true)]
        func execute(_ call: ToolCall) async -> ToolResult {
            ToolResult(callID: call.id, name: call.name, text: String(repeating: "x", count: 30_000), isError: false)
        }
    }

    private static func sse(_ payloads: [String]) -> StubRegistry.Reply {
        StubRegistry.Reply(body: Data(payloads.map { "data: \($0)\n\n" }.joined().utf8))
    }

    private static func pageCall(_ n: Int) -> String {
        let call: [String: Any] = [
            "index": 0, "id": "c\(n)", "type": "function",
            "function": ["name": "page", "arguments": #"{"url":"https://example.com/\#(n)"}"#],
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["tool_calls": [call]]]]]), as: UTF8.self)
    }

    /// Agent design 3.4 on a cloud model with a 20,000-token window: results go back whole, and the oldest is cleared
    /// to a stub that keeps its address only once clearing frees at least 8,000 tokens.
    @Test func aLongRunClearsTheOldestPageInOneLargeStep() async throws {
        let bodies = Bodies()
        let counter = Counter()
        let api = StubbedAPI { request in
            bodies.add(request)
            let n = counter.next()
            if n <= 4 { return Self.sse([Self.pageCall(n), #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#, "[DONE]"]) }
            return Self.sse([#"{"choices":[{"delta":{"content":"Done."}}]}"#, #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#, "[DONE]"])
        }
        let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
        let model = ModelDescriptor(
            id: "anyrouter/test/long", source: .anyrouter, displayName: "Long", contextLength: 20_000,
            capabilities: ["chat", "tools"], sizeBytes: nil, isInstalled: true)
        var deltas: [ChatDelta] = []
        for try await delta in engine.stream(
            model: model, messages: [ChatMessage(role: .user, content: "read four pages")], params: GenerationParams(), tools: Pages()) {
            deltas.append(delta)
        }
        #expect(deltas.last == .done(finishReason: "stop"))
        #expect(bodies.list.count == 5)
        #expect(bodies.toolMessages(3).allSatisfy { $0.count == 30_000 }, "three pages over the window: one stub would free too little")
        let last = bodies.toolMessages(4)
        #expect(last.first == "[Result cleared: page https://example.com/1, 30000 characters]")
        #expect(last.dropFirst().allSatisfy { $0.count == 30_000 })
    }

    /// A subagent runs on the same model and key, with only its own messages, prompt and tools (PLAN D28 S1).
    @Test func aSubagentStepUsesTheSameModelWithItsOwnMessagesAndTools() throws {
        let engine = AnyRouterEngine(tokens: FakeTokens("k"))
        let model = ModelDescriptor(
            id: "anyrouter/test/sub", source: .anyrouter, displayName: "Sub", contextLength: 20_000,
            capabilities: ["chat", "tools"], sizeBytes: nil, isInstalled: true)
        let specs = [ToolSpec(name: "web_search", title: nil, description: "Search", inputSchemaJSON: "{}", isReadOnly: true)]
        let made = engine.childStep(
            model: model, messages: [ChatMessage(role: .user, content: "Find it")], params: GenerationParams(systemPrompt: "Research."), specs: specs)
        let step = try #require(made as? AnyRouterStep)
        #expect(step.model.id == model.id)
        #expect(step.messages.map(\.content) == ["Find it"])
        #expect(step.params.systemPrompt == "Research.")
        #expect(step.specs == specs)
    }
}
