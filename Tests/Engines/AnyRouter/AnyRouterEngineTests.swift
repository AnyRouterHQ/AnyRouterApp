import Foundation
import Testing
@testable import AnyRouter

final class FakeTokens: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?
    private var clears = 0

    init(_ token: String?) { current = token }

    func token() -> String? { lock.withLock { current } }
    func clear() { lock.withLock { current = nil; clears += 1 } }
    var clearCount: Int { lock.withLock { clears } }
}

private func json(_ text: String, status: Int = 200) -> StubRegistry.Reply {
    StubRegistry.Reply(status: status, body: Data(text.utf8))
}

private func sse(_ payloads: [String], status: Int = 200) -> StubRegistry.Reply {
    json(payloads.map { "data: \($0)\n\n" }.joined(), status: status)
}

private func chunk(_ text: String) -> String { #"{"choices":[{"delta":{"content":"\#(text)"}}]}"# }

private func collect(_ stream: AsyncThrowingStream<ChatDelta, Error>) async -> (deltas: [ChatDelta], error: Error?) {
    var deltas: [ChatDelta] = []
    do {
        for try await delta in stream { deltas.append(delta) }
        return (deltas, nil)
    } catch {
        return (deltas, error)
    }
}

private let model = testModel(id: "anyrouter/openai/mini", source: .anyrouter)

struct AnyRouterEngineModelsTests {
    private let body = #"{"data":[{"id":"openai/mini","category":"text"},{"id":"x/embed","category":"embedding"}]}"#

    @Test func signedInUserGetsUsableChatModelsAndTheirKeyIsSent() async throws {
        let seen = Flag()
        let api = StubbedAPI { request in
            seen.value = request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ar-1"
            return json(body)
        }
        let engine = AnyRouterEngine(tokens: FakeTokens("sk-ar-1"), config: api.config, session: api.session)
        let models = try await engine.availableModels()
        #expect(models.map(\.id) == ["anyrouter/openai/mini"])
        #expect(models.allSatisfy(\.isInstalled))
        #expect(seen.value)
    }

    @Test func signedOutUserSeesModelsButCannotUseThemAndSendsNoKey() async throws {
        let leaked = Flag()
        let api = StubbedAPI { request in
            leaked.value = request.value(forHTTPHeaderField: "Authorization") != nil
            return json(body)
        }
        let engine = AnyRouterEngine(tokens: FakeTokens(nil), config: api.config, session: api.session)
        let models = try await engine.availableModels()
        #expect(models.count == 1)
        #expect(models.allSatisfy { !$0.isInstalled })
        #expect(!leaked.value)
    }

    @Test func rejectedKeyIsClearedAndReported() async {
        let tokens = FakeTokens("sk-ar-old")
        let notified = Flag()
        let api = StubbedAPI { _ in json(#"{"error":{"message":"Key revoked"}}"#, status: 401) }
        let engine = AnyRouterEngine(tokens: tokens, config: api.config, session: api.session) { notified.value = true }
        do {
            _ = try await engine.availableModels()
            Issue.record("expected an error")
        } catch {
            #expect(error as? AnyRouterError == .http(status: 401, message: "Key revoked"))
        }
        #expect(tokens.token() == nil)
        #expect(notified.value)
    }

    @Test func unauthorizedWithoutKeyDoesNotTouchSignInState() async {
        let tokens = FakeTokens(nil)
        let notified = Flag()
        let api = StubbedAPI { _ in json("{}", status: 401) }
        let engine = AnyRouterEngine(tokens: tokens, config: api.config, session: api.session) { notified.value = true }
        _ = try? await engine.availableModels()
        #expect(tokens.clearCount == 0)
        #expect(!notified.value)
    }

    @Test func serverErrorSurfacesItsMessage() async {
        let api = StubbedAPI { _ in json("", status: 502) }
        let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
        do {
            _ = try await engine.availableModels()
            Issue.record("expected an error")
        } catch {
            #expect(error as? AnyRouterError == .http(status: 502, message: "Request failed (HTTP 502)."))
        }
    }
}

struct AnyRouterEngineStreamTests {
    private func engine(_ api: StubbedAPI, tokens: FakeTokens = FakeTokens("sk-ar-1"),
                        onUnauthorized: @escaping @Sendable () async -> Void = {}) -> AnyRouterEngine {
        AnyRouterEngine(tokens: tokens, config: api.config, session: api.session, onUnauthorized: onUnauthorized)
    }

    private func run(_ engine: AnyRouterEngine) async -> (deltas: [ChatDelta], error: Error?) {
        await collect(engine.stream(model: model, messages: [ChatMessage(role: .user, content: "hi")], params: GenerationParams()))
    }

    @Test func streamsTextUsageAndDone() async {
        let api = StubbedAPI { _ in
            sse([chunk("Hel"), chunk("lo"), #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
                 #"{"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":2}}"#, "[DONE]"])
        }
        let result = await run(engine(api))
        #expect(result.error == nil)
        #expect(result.deltas == [.text("Hel"), .text("lo"), .usage(prompt: 4, completion: 2), .done(finishReason: "stop")])
    }

    @Test func connectionEndingWithoutDoneStillFinishesTheAnswer() async {
        let api = StubbedAPI { _ in
            // The last event has no blank line after it and there is no [DONE].
            StubRegistry.Reply(body: Data("data: \(chunk("a"))\n\ndata: \(chunk("b"))".utf8))
        }
        let result = await run(engine(api))
        #expect(result.error == nil)
        #expect(result.deltas == [.text("a"), .text("b"), .done(finishReason: nil)])
    }

    @Test func requestCarriesModelAndKey() async {
        let ok = Flag()
        let api = StubbedAPI { request in
            ok.value = request.url?.path == "/api/v1/chat/completions"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ar-1"
            return sse(["[DONE]"])
        }
        _ = await run(engine(api))
        #expect(ok.value)
    }

    @Test func signedOutUserGetsASignInErrorAndNoRequest() async {
        let hit = Flag()
        let api = StubbedAPI { _ in hit.value = true; return sse(["[DONE]"]) }
        let result = await run(engine(api, tokens: FakeTokens(nil)))
        #expect(result.error as? AnyRouterError == .signedOut)
        #expect(!hit.value)
    }

    @Test func expiredKeyDuringChatSignsTheUserOut() async {
        let tokens = FakeTokens("sk-ar-1")
        let notified = Flag()
        let api = StubbedAPI { _ in json(#"{"error":{"message":"expired"}}"#, status: 401) }
        let result = await run(engine(api, tokens: tokens) { notified.value = true })
        #expect(result.error as? AnyRouterError == .signedOut)
        #expect(tokens.token() == nil)
        #expect(notified.value)
    }

    @Test func httpErrorShowsServerMessage() async {
        let api = StubbedAPI { _ in json(#"{"error":{"message":"Out of credits"}}"#, status: 402) }
        let result = await run(engine(api))
        #expect(result.error as? AnyRouterError == .http(status: 402, message: "Out of credits"))
    }

    @Test func hugeErrorBodyIsCappedAndStillReported() async {
        let api = StubbedAPI { _ in json(String(repeating: "x", count: 40_000), status: 500) }
        let result = await run(engine(api))
        #expect(result.error as? AnyRouterError == .http(status: 500, message: "Request failed (HTTP 500)."))
    }

    @Test func errorChunkMidStreamKeepsEarlierTextThenFails() async {
        let api = StubbedAPI { _ in sse([chunk("ok"), #"{"error":{"message":"boom"}}"#]) }
        let result = await run(engine(api))
        #expect(result.deltas == [.text("ok")])
        #expect(result.error as? AnyRouterError == .stream("boom"))
    }

    @Test func transportFailureIsReported() async {
        // No handler registered for this host: the stub fails the connection.
        let session = StubbedAPI { _ in json("") }.session
        let config = AnyRouterConfig(baseURL: URL(string: "https://nobody-\(UUID().uuidString.lowercased()).test/api/v1")!)
        let result = await run(AnyRouterEngine(tokens: FakeTokens("k"), config: config, session: session))
        #expect((result.error as? URLError)?.code == .cannotFindHost)
    }

    @Test func droppingTheConsumerClosesTheConnection() async throws {
        let api = StubbedAPI { _ in
            StubRegistry.Reply(body: Data("data: \(chunk("first"))\n\n".utf8), hangs: true)
        }
        let sut = engine(api)
        let first = Flag()
        let consumer = Task {
            for try await delta in sut.stream(model: model, messages: [], params: GenerationParams()) {
                if delta == .text("first") { first.value = true }
            }
        }
        for _ in 0..<500 where !first.value { try await Task.sleep(for: .milliseconds(10)) }
        #expect(first.value)
        consumer.cancel()
        _ = await consumer.result
        for _ in 0..<500 where !StubRegistry.shared.wasStopped(host: api.host) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(StubRegistry.shared.wasStopped(host: api.host))
    }
}

struct AnyRouterRequestTests {
    @Test func maxTokensAndSystemPromptReachTheWire() throws {
        let engine = AnyRouterEngine(tokens: FakeTokens("k"))
        var params = GenerationParams()
        params.maxTokens = 64
        params.systemPrompt = "Be brief."
        let request = try engine.makeChatRequest(key: "k", model: model, messages: [ChatMessage(role: .user, content: "hi")], params: params)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["max_tokens"] as? Int == 64)
        #expect((body["messages"] as? [[String: String]])?.first?["content"] == "Be brief.")
    }

    @Test func emptySystemPromptIsNotSent() throws {
        let engine = AnyRouterEngine(tokens: FakeTokens("k"))
        var params = GenerationParams()
        params.systemPrompt = ""
        let request = try engine.makeChatRequest(key: "k", model: model, messages: [ChatMessage(role: .user, content: "hi")], params: params)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((body["messages"] as? [[String: String]])?.map { $0["role"] } == ["user"])
        #expect(body["max_tokens"] == nil)
    }

    @Test func modelIDWithoutOurPrefixPassesThrough() {
        #expect(AnyRouterEngine.wireModelID("openai/mini") == "openai/mini")
        #expect(AnyRouterEngine.wireModelID("anyrouter/openai/mini") == "openai/mini")
    }
}

struct AnyRouterErrorTests {
    @Test func everyErrorHasAUserFacingMessage() {
        #expect(AnyRouterError.signedOut.errorDescription == "Sign in with AnyRouter to use cloud models.")
        #expect(AnyRouterError.http(status: 500, message: "down").errorDescription == "down")
        #expect(AnyRouterError.stream("cut").errorDescription == "cut")
        #expect(AnyRouterError.badResponse.errorDescription == "AnyRouter returned an unexpected response.")
    }

    @Test func messageFallsBackThroughKnownShapes() {
        func message(_ text: String) -> String { AnyRouterError.message(from: Data(text.utf8), status: 400) }
        #expect(message(#"{"message":"top level"}"#) == "top level")
        #expect(message(#"{"error":"plain"}"#) == "plain")
        #expect(message(#"{"error":{"message":""}}"#) == "Request failed (HTTP 400).")
        #expect(message("[]") == "Request failed (HTTP 400).")
    }

    @Test func configVersionIsNeverEmpty() {
        #expect(!AnyRouterConfig.standard.version.isEmpty)
    }
}
