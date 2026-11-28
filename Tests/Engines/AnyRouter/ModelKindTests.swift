import Foundation
import Testing
@testable import AnyRouter

/// Catalog entries copied from the live `GET /api/v1/models`, trimmed to the fields we read.
enum CatalogSample {
    static let decision = #"{"id":"anyrouter/decision","name":"AnyRouter Decision","category":"text","context_length":393216,"capabilities":["systemone"],"supported_parameters":["state","model","questions","service_tier","max_len"],"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"]}}"#
    static let visionDecision = #"{"id":"google/gemini-decision-1","name":"Gemini Decision 1","category":"text","capabilities":["systemone"],"architecture":{"modality":"text->text","input_modalities":["text","image","audio"],"output_modalities":["text"]}}"#
    static let chat = #"{"id":"anyrouter/byok","name":"AnyRouter BYOK","category":"text","context_length":2000000,"capabilities":["chat","streaming","coding","function-calling","vision"],"supported_parameters":["max_tokens","temperature","stop","tools","tool_choice","top_p"],"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["text"]}}"#
    static let multimodal = #"{"id":"agents-a1/agents-a1-free","name":"Agents A1","category":"multimodal","context_length":262144,"capabilities":["chat","streaming","agentic","coding","vision"],"supported_parameters":["max_tokens","temperature","top_p","stop","stream"],"architecture":{"modality":"text+image->text","input_modalities":["text","image"],"output_modalities":["text"]}}"#
    static let embedding = #"{"id":"aiteamvn/vietnamese-embedding","name":"Vietnamese Embedding","category":"embedding","context_length":8000,"capabilities":["embedding"],"supported_parameters":["input","model","encoding_format"],"architecture":{"modality":"text->embedding","input_modalities":["text"],"output_modalities":["embeddings"]}}"#
    static let rerank = #"{"id":"cohere/rerank-multilingual-v3.0","name":"Rerank Multilingual 3.0","category":"rerank","context_length":4096,"capabilities":["rerank"],"supported_parameters":["max_tokens","temperature","top_p","stop","stream"],"architecture":{"modality":"text->text","input_modalities":["text"],"output_modalities":["scores"]}}"#

    static func list(_ items: String...) -> Data { Data(#"{"object":"list","data":[\#(items.joined(separator: ","))]}"#.utf8) }
}

struct ModelKindTests {
    private func kind(_ json: String) throws -> ModelKind {
        try JSONDecoder().decode(ModelsResponse.Item.self, from: Data(json.utf8)).kind
    }

    @Test func realSamplesClassifyByKind() throws {
        #expect(try kind(CatalogSample.decision) == .decision)
        #expect(try kind(CatalogSample.chat) == .chat)
        #expect(try kind(CatalogSample.multimodal) == .chat)
        #expect(try kind(CatalogSample.embedding) == .embedding)
        #expect(try kind(CatalogSample.rerank) == .rerank)
    }

    @Test func aDecisionModelIsNotMistakenForChatBecauseItsCategoryIsText() {
        // Same category and output type as a chat model: only the capability or parameter tells them apart.
        #expect(ModelKind.classify(category: "text", outputModalities: ["text"], capabilities: ["systemone"], supportedParameters: []) == .decision)
        #expect(ModelKind.classify(category: "text", outputModalities: ["text"], capabilities: [], supportedParameters: ["state", "questions"]) == .decision)
        #expect(ModelKind.classify(category: "text", outputModalities: ["text"], capabilities: ["chat"], supportedParameters: ["tools"]) == .chat)
    }

    @Test func embeddingAndRerankAreFoundByCategoryOrByOutputType() {
        #expect(ModelKind.classify(category: "embedding", outputModalities: [], capabilities: [], supportedParameters: []) == .embedding)
        #expect(ModelKind.classify(category: nil, outputModalities: ["embeddings"], capabilities: [], supportedParameters: []) == .embedding)
        #expect(ModelKind.classify(category: "rerank", outputModalities: [], capabilities: [], supportedParameters: []) == .rerank)
        #expect(ModelKind.classify(category: nil, outputModalities: ["scores"], capabilities: [], supportedParameters: []) == .rerank)
    }

    @Test func anEntryWithNoMetadataIsChat() throws {
        #expect(try kind(#"{"id":"x/y"}"#) == .chat)
    }

    @Test func decisionRulesWinOverEmbeddingOutput() {
        #expect(ModelKind.classify(category: "embedding", outputModalities: ["embeddings"], capabilities: ["systemone"], supportedParameters: []) == .decision)
    }

    @Test func theChatListHoldsOnlyChatModelsAndTheDecisionListOnlyDecisionModels() throws {
        let data = CatalogSample.list(
            CatalogSample.decision, CatalogSample.visionDecision, CatalogSample.chat, CatalogSample.multimodal,
            CatalogSample.embedding, CatalogSample.rerank, #"{"id":"x/unnamed-decision","capabilities":["systemone"]}"#)
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        #expect(response.descriptors(usable: true).map(\.id) == ["anyrouter/anyrouter/byok", "anyrouter/agents-a1/agents-a1-free"])
        let decisions = response.decisionDescriptors(usable: true)
        #expect(decisions.map(\.wireID) == ["anyrouter/decision", "google/gemini-decision-1", "x/unnamed-decision"])
        #expect(decisions.map(\.displayName) == ["AnyRouter Decision", "Gemini Decision 1", "x/unnamed-decision"])
        // Only the model whose input takes images is offered when a photo is attached.
        #expect(decisions.map(\.capabilities) == [["decision"], ["decision", "vision"], ["decision"]])
        #expect(decisions.allSatisfy { $0.source == .anyrouter && $0.cloud != nil && $0.isInstalled })
    }

    /// Signed out a decision model is listed, but no mini app may pick it.
    @Test func signedOutDecisionModelsAreListedButNotUsable() throws {
        let response = try JSONDecoder().decode(ModelsResponse.self, from: CatalogSample.list(CatalogSample.decision))
        #expect(response.decisionDescriptors(usable: false).map(\.isInstalled) == [false])
    }
}

struct AnyRouterEngineKindTests {
    private func reply(_ data: Data) -> StubRegistry.Reply { StubRegistry.Reply(status: 200, body: data) }

    @Test func availableModelsSkipsDecisionEmbeddingAndRerankModels() async throws {
        let data = CatalogSample.list(CatalogSample.decision, CatalogSample.chat, CatalogSample.embedding, CatalogSample.rerank)
        let api = StubbedAPI { _ in reply(data) }
        let engine = AnyRouterEngine(tokens: FakeTokens("sk-ar-1"), config: api.config, session: api.session)
        #expect(try await engine.availableModels().map(\.id) == ["anyrouter/anyrouter/byok"])
    }

    @Test func decisionModelsComeFromTheSameCatalog() async throws {
        let data = CatalogSample.list(CatalogSample.chat, CatalogSample.decision)
        let api = StubbedAPI { _ in reply(data) }
        let engine = AnyRouterEngine(tokens: FakeTokens(nil), config: api.config, session: api.session)
        #expect(try await engine.decisionModels().map(\.wireID) == ["anyrouter/decision"])
    }
}
