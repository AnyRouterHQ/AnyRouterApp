import Foundation
import Testing
@testable import AnyRouter

private func sse(_ payloads: [String]) -> StubRegistry.Reply {
    StubRegistry.Reply(body: Data(payloads.map { "data: \($0)\n\n" }.joined().utf8))
}

private func text(_ piece: String) -> String { #"{"choices":[{"delta":{"content":"\#(piece)"}}]}"# }

/// A streamed fragment of tool call `index`.
private func fragment(index: Int, id: String? = nil, name: String? = nil, arguments: String? = nil) -> String {
    var function: [String: String] = [:]
    if let name { function["name"] = name }
    if let arguments { function["arguments"] = arguments }
    var call: [String: Any] = ["index": index, "function": function]
    if let id { call["id"] = id; call["type"] = "function" }
    let chunk: [String: Any] = ["choices": [["delta": ["tool_calls": [call]]]]]
    return String(decoding: try! JSONSerialization.data(withJSONObject: chunk), as: UTF8.self)
}

private let finishToolCalls = #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#
private let finishStop = #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#
private func usage(_ prompt: Int, _ completion: Int) -> String {
    #"{"choices":[],"usage":{"prompt_tokens":\#(prompt),"completion_tokens":\#(completion)}}"#
}

private func body(of request: URLRequest) -> [String: Any] {
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
    return (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

/// Records what each request carried.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [[String: Any]] = []
    func add(_ request: URLRequest) { let b = body(of: request); lock.withLock { all.append(b) } }
    var bodies: [[String: Any]] { lock.withLock { all } }
}

private final class ScriptedHost: ToolHost, @unchecked Sendable {
    let specs: [ToolSpec]
    private let lock = NSLock()
    private var received: [ToolCall] = []
    private let run: @Sendable (ToolCall) async -> ToolResult

    init(specs: [ToolSpec] = [ScriptedHost.search], run: @escaping @Sendable (ToolCall) async -> ToolResult = { call in
        ToolResult(callID: call.id, name: call.name, text: "result of \(call.name)", isError: false)
    }) {
        self.specs = specs
        self.run = run
    }

    static let search = ToolSpec(
        name: "web_search", title: nil, description: "Search the web",
        inputSchemaJSON: #"{"type":"object","properties":{"q":{"type":"string"}},"required":["q"]}"#, isReadOnly: true
    )

    var calls: [ToolCall] { lock.withLock { received } }

    func execute(_ call: ToolCall) async -> ToolResult {
        lock.withLock { received.append(call) }
        return await run(call)
    }
}

private let model = testModel(id: "anyrouter/openai/mini", source: .anyrouter)

private func collect(
    _ api: StubbedAPI, host: (any ToolHost)?, messages: [ChatMessage] = [ChatMessage(role: .user, content: "hi")]
) async -> (deltas: [ChatDelta], error: Error?) {
    let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
    var deltas: [ChatDelta] = []
    do {
        for try await delta in engine.stream(model: model, messages: messages, params: GenerationParams(), tools: host) {
            deltas.append(delta)
        }
        return (deltas, nil)
    } catch {
        return (deltas, error)
    }
}

struct AnyRouterToolLoopTests {
    @Test func callIsRunAndItsResultGoesBackBeforeTheAnswer() async throws {
        let seen = Seen()
        let counter = Counter()
        let api = StubbedAPI { request in
            seen.add(request)
            if counter.next() == 1 {
                return sse([
                    fragment(index: 0, id: "call_a", name: "web_search", arguments: ""),
                    fragment(index: 0, arguments: #"{"q":"#),
                    fragment(index: 0, arguments: #""swift"}"#),
                    finishToolCalls, usage(10, 3), "[DONE]",
                ])
            }
            return sse([text("Swift "), text("is great"), finishStop, usage(20, 4), "[DONE]"])
        }
        let host = ScriptedHost()
        let result = await collect(api, host: host)

        #expect(result.error == nil)
        let call = ToolCall(id: "call_a", name: "web_search", argumentsJSON: #"{"q":"swift"}"#)
        #expect(host.calls == [call])
        #expect(result.deltas == [
            .toolCall(call),
            .toolResult(ToolResult(callID: "call_a", name: "web_search", text: "result of web_search", isError: false)),
            .text("Swift "), .text("is great"),
            .usage(prompt: 30, completion: 7),
            .done(finishReason: "stop"),
        ])

        let bodies = seen.bodies
        #expect(bodies.count == 2)
        // First request offers the tool with its schema.
        let tools = try #require(bodies[0]["tools"] as? [[String: Any]])
        let function = try #require(tools.first?["function"] as? [String: Any])
        #expect(function["name"] as? String == "web_search")
        #expect(((function["parameters"] as? [String: Any])?["required"] as? [String]) == ["q"])
        #expect(bodies[0]["tool_choice"] as? String == "auto")
        // Second request replays the assistant's tool call and the result.
        let messages = try #require(bodies[1]["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "tool"])
        let assistant = messages[1]
        #expect(assistant["content"] is NSNull)
        let replayed = try #require((assistant["tool_calls"] as? [[String: Any]])?.first)
        #expect(replayed["id"] as? String == "call_a")
        #expect((replayed["function"] as? [String: Any])?["arguments"] as? String == #"{"q":"swift"}"#)
        #expect(messages[2]["tool_call_id"] as? String == "call_a")
        #expect(messages[2]["content"] as? String == "result of web_search")
    }

    /// G4 (agent design E6, cloud half): after a relaunch the waiting call runs once and the next request carries its result.
    @Test func aResumedRunRunsOnlyTheWaitingCallAndSendsItsResult() async throws {
        let seen = Seen()
        let api = StubbedAPI { request in
            seen.add(request)
            return sse([text("Sent."), finishStop, usage(5, 1), "[DONE]"])
        }
        let host = ScriptedHost()
        let call = ToolCall(id: "call_a", name: "web_search", argumentsJSON: #"{"q":"swift"}"#)
        let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
        let resume = AgentResume(rounds: [], pending: AgentRound(text: "", calls: [call], results: []))
        var deltas: [ChatDelta] = []
        for try await delta in engine.stream(
            model: model, messages: [ChatMessage(role: .user, content: "hi")], params: GenerationParams(), tools: host, resuming: resume) {
            deltas.append(delta)
        }
        #expect(host.calls == [call])
        #expect(deltas.first == .toolCall(call))
        let bodies = seen.bodies
        #expect(bodies.count == 1, "no request before the call runs")
        let messages = try #require(bodies.first?["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "tool"])
        #expect(messages.last?["tool_call_id"] as? String == "call_a")
        #expect(messages.last?["content"] as? String == "result of web_search")
    }

    @Test func textBeforeTheCallIsKeptAndSeveralCallsRunInOrder() async throws {
        let seen = Seen()
        let counter = Counter()
        let api = StubbedAPI { request in
            seen.add(request)
            if counter.next() == 1 {
                return sse([
                    text("Let me check. "),
                    fragment(index: 0, id: "c0", name: "web_search", arguments: #"{"q":"a"}"#),
                    fragment(index: 1, id: "c1", name: "web_search", arguments: #"{"q":"b"}"#),
                    finishToolCalls, "[DONE]",
                ])
            }
            return sse([text("Done."), finishStop, "[DONE]"])
        }
        let host = ScriptedHost()
        let result = await collect(api, host: host)

        #expect(host.calls.map(\.id) == ["c0", "c1"])
        #expect(result.deltas.first == .text("Let me check. "))
        let messages = try #require(seen.bodies[1]["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "tool", "tool"])
        #expect(messages[1]["content"] as? String == "Let me check. ")
        #expect(messages.dropFirst(2).map { $0["tool_call_id"] as? String } == ["c0", "c1"])
    }

    @Test func aFailedToolIsReportedToTheModelNotThrown() async throws {
        let seen = Seen()
        let counter = Counter()
        let api = StubbedAPI { request in
            seen.add(request)
            return counter.next() == 1
                ? sse([fragment(index: 0, id: "c", name: "web_search", arguments: "{}"), finishToolCalls, "[DONE]"])
                : sse([text("Sorry."), finishStop, "[DONE]"])
        }
        let host = ScriptedHost { call in ToolResult(callID: call.id, name: call.name, text: "HTTP 500: boom", isError: true) }
        let result = await collect(api, host: host)
        #expect(result.error == nil)
        let messages = try #require(seen.bodies[1]["messages"] as? [[String: Any]])
        #expect(messages.last?["content"] as? String == "HTTP 500: boom")
    }

    @Test func withoutAHostNoToolsAreSentAndCallsAreIgnored() async throws {
        let seen = Seen()
        let api = StubbedAPI { request in
            seen.add(request)
            return sse([fragment(index: 0, id: "c", name: "web_search", arguments: "{}"), finishToolCalls, "[DONE]"])
        }
        let result = await collect(api, host: nil)
        #expect(result.error == nil)
        #expect(seen.bodies.count == 1)
        #expect(seen.bodies[0]["tools"] == nil)
        #expect(seen.bodies[0]["tool_choice"] == nil)
        #expect(result.deltas == [.done(finishReason: "tool_calls")])
    }

    @Test func aHostWithNoToolsSendsNoToolsField() async {
        let seen = Seen()
        let api = StubbedAPI { request in seen.add(request); return sse([text("hi"), "[DONE]"]) }
        _ = await collect(api, host: ScriptedHost(specs: []))
        #expect(seen.bodies.first?["tools"] == nil)
    }

    @Test func aModelThatNeverStopsCallingToolsIsCutOffAfterEightRounds() async throws {
        let seen = Seen()
        let counter = Counter()
        let api = StubbedAPI { request in
            seen.add(request)
            let n = counter.next()
            if n <= AnyRouterEngine.maxToolSteps {
                return sse([fragment(index: 0, id: "c\(n)", name: "web_search", arguments: "{}"), finishToolCalls, "[DONE]"])
            }
            return sse([text("Final answer."), finishStop, "[DONE]"])
        }
        let host = ScriptedHost()
        let result = await collect(api, host: host)

        #expect(host.calls.count == 8)
        #expect(seen.bodies.count == 9)
        // The last request still lists the tools (the history mentions them) but forbids calling one.
        #expect(seen.bodies[8]["tool_choice"] as? String == "none")
        #expect(seen.bodies[7]["tool_choice"] as? String == "auto")
        #expect(result.deltas.last == .done(finishReason: "stop"))
        #expect(result.deltas.contains(.text("Final answer.")))
    }

    @Test func stopDuringAToolCallEndsTheReplyWithoutAnotherRequest() async throws {
        let seen = Seen()
        let api = StubbedAPI { request in
            seen.add(request)
            return sse([fragment(index: 0, id: "c", name: "web_search", arguments: "{}"), finishToolCalls, "[DONE]"])
        }
        let started = Flag()
        let host = ScriptedHost { call in
            started.value = true
            // Like a real MCP call: gives up when its task is cancelled.
            try? await Task.sleep(for: .seconds(30))
            return ToolResult(callID: call.id, name: call.name, text: "The tool call was cancelled.", isError: true)
        }
        let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
        let finished = Flag()
        let consumer = Task {
            for try await _ in engine.stream(model: model, messages: [], params: GenerationParams(), tools: host) {}
            finished.value = true
        }
        for _ in 0..<500 where !started.value { try await Task.sleep(for: .milliseconds(10)) }
        #expect(started.value)
        consumer.cancel()
        _ = await consumer.result
        #expect(seen.bodies.count == 1)
    }

    @Test func tokenExpiredBetweenRoundsSignsTheUserOut() async {
        let tokens = FakeTokens("k")
        let counter = Counter()
        let api = StubbedAPI { _ in
            counter.next() == 1
                ? sse([fragment(index: 0, id: "c", name: "web_search", arguments: "{}"), finishToolCalls, "[DONE]"])
                : StubRegistry.Reply(status: 401, body: Data(#"{"error":{"message":"expired"}}"#.utf8))
        }
        let engine = AnyRouterEngine(tokens: tokens, config: api.config, session: api.session)
        var failure: Error?
        do {
            for try await _ in engine.stream(model: model, messages: [], params: GenerationParams(), tools: ScriptedHost()) {}
        } catch {
            failure = error
        }
        #expect(failure as? AnyRouterError == .signedOut)
        #expect(tokens.token() == nil)
    }
}

struct ToolCallDecodingTests {
    private func decode(_ payloads: [String]) throws -> ChatChunkDecoder {
        var decoder = ChatChunkDecoder()
        for payload in payloads { _ = try decoder.decode(payload) }
        return decoder
    }

    @Test func fragmentsAreJoinedByIndex() throws {
        let decoder = try decode([
            fragment(index: 1, id: "b", name: "two", arguments: "{}"),
            fragment(index: 0, id: "a", name: "one", arguments: #"{"x":"#),
            fragment(index: 0, arguments: "1}"),
        ])
        #expect(decoder.toolCalls == [
            ToolCall(id: "a", name: "one", argumentsJSON: #"{"x":1}"#),
            ToolCall(id: "b", name: "two", argumentsJSON: "{}"),
        ])
    }

    @Test func missingIdEmptyArgumentsAndRepeatedNamesAreHandled() throws {
        let decoder = try decode([
            fragment(index: 0, name: "ping", arguments: ""),
            fragment(index: 0, name: "ping"),
            fragment(index: 1, arguments: "{}"),  // never got a name: dropped
        ])
        let calls = decoder.toolCalls
        #expect(calls.count == 1)
        #expect(calls[0].name == "ping")
        #expect(calls[0].argumentsJSON == "{}")
        #expect(calls[0].id.hasPrefix("call_"))
    }

    @Test func providersThatOmitTheIndexStartANewCallOnANewId() throws {
        func raw(_ id: String?, _ name: String?, _ arguments: String) -> String {
            var function: [String: Any] = ["arguments": arguments]
            if let name { function["name"] = name }
            var call: [String: Any] = ["function": function]
            if let id { call["id"] = id }
            return String(decoding: try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["tool_calls": [call]]]]]), as: UTF8.self)
        }
        let decoder = try decode([raw("x", "first", "{"), raw(nil, nil, "}"), raw("y", "second", "{}")])
        #expect(decoder.toolCalls.map(\.name) == ["first", "second"])
        #expect(decoder.toolCalls.first?.argumentsJSON == "{}")
    }

    @Test func plainTextChunksProduceNoToolCalls() throws {
        #expect(try decode([text("hi"), finishStop]).toolCalls.isEmpty)
    }
}

struct ToolWireTests {
    @Test func schemaIsSentAsAnObject() throws {
        let wire = AnyRouterEngine.wireTool(ScriptedHost.search)
        let function = try #require(wire["function"] as? [String: Any])
        #expect(wire["type"] as? String == "function")
        #expect(function["description"] as? String == "Search the web")
        #expect((function["parameters"] as? [String: Any])?["type"] as? String == "object")
    }

    @Test func aBrokenSchemaDegradesToNoArguments() throws {
        let broken = ToolSpec(name: "t", title: nil, description: "d", inputSchemaJSON: "not json", isReadOnly: true)
        let function = try #require(AnyRouterEngine.wireTool(broken)["function"] as? [String: Any])
        #expect((function["parameters"] as? [String: Any])?["type"] as? String == "object")
    }

    @Test func functionCallingTagBecomesTheToolsCapability() {
        #expect(ModelsResponse.normalized(["chat", "function-calling"]).contains("tools"))
        #expect(ModelsResponse.normalized(["chat", "function_calling"]).contains("tools"))
        #expect(!ModelsResponse.normalized(["chat", "vision"]).contains("tools"))
        #expect(ModelsResponse.normalized(["chat", "function-calling"]).contains("function-calling"))
    }
}
