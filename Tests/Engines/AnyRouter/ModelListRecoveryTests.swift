import Foundation
import Testing

@testable import AnyRouter

/// The catalog the picker is built from. A bad entry or a bad body must never leave the person with an empty list
/// and no reason.
struct ModelListRecoveryTests {
    private func recorded() throws -> Data {
        // Tests/Engines/AnyRouter/<this file>: four steps up is the repo root.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/anyrouter-models-live.json"))
    }

    @Test func aFreshlyRecordedCatalogReadsWithoutSkippingAnything() throws {
        let response = try JSONDecoder().decode(ModelsResponse.self, from: recorded())
        #expect(response.data.count == 12)
        #expect(response.skipped == 0)
        let chat = response.descriptors(usable: true).map(\.id)
        #expect(chat.contains("anyrouter/anyrouter/auto"))
        #expect(chat.contains("anyrouter/openai/gpt-6.2-sol"))
        #expect(!chat.contains("anyrouter/cohere/rerank-v3.5"), "rerank models stay out of the chat list")
        #expect(response.decisionModels().map(\.id) == ["anyrouter/decision", "scira/amos-1-large"])
    }

    @Test func oneUnreadableEntryDoesNotDropTheCatalog() throws {
        let body = """
            {"data":[
              {"id":"openai/ok-1","category":"text"},
              {"id":"bad/created","category":"text","created":"yesterday"},
              {"name":"an entry without an id"},
              "not even an object",
              {"id":"bad/context","context_length":"huge"},
              {"id":"openai/ok-2","category":"text"}
            ]}
            """
        let response = try JSONDecoder().decode(ModelsResponse.self, from: Data(body.utf8))
        #expect(response.descriptors(usable: true).map(\.id) == ["anyrouter/openai/ok-1", "anyrouter/openai/ok-2"])
        #expect(response.skipped == 4)
    }

    @Test func aCatalogWithoutADataListIsNotACatalog() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ModelsResponse.self, from: Data(#"{"object":"list"}"#.utf8))
        }
    }

    @Test func theEngineListsTheReadableModelsWhenOneEntryIsOdd() async throws {
        let body = #"{"data":[{"id":"openai/ok","category":"text"},{"id":"bad/created","created":"yesterday"}]}"#
        let api = StubbedAPI { _ in StubRegistry.Reply(body: Data(body.utf8)) }
        let engine = AnyRouterEngine(tokens: FakeTokens("sk-ar-1"), config: api.config, session: api.session)
        #expect(try await engine.availableModels().map(\.id) == ["anyrouter/openai/ok"])
    }

    @Test func aBodyThatIsNotACatalogFailsWithAReadableReason() async {
        let api = StubbedAPI { _ in StubRegistry.Reply(body: Data("<html>Bad gateway</html>".utf8)) }
        let engine = AnyRouterEngine(tokens: FakeTokens("sk-ar-1"), config: api.config, session: api.session)
        do {
            _ = try await engine.availableModels()
            Issue.record("expected an error")
        } catch {
            #expect(error as? AnyRouterError == .badResponse)
            #expect(error.localizedDescription == "AnyRouter returned an unexpected response.")
        }
    }
}
