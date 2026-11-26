import Foundation
import Testing
@testable import AnyRouter

/// The catalog fields the detail screen reads. They are shown only, so an odd shape must never break the list.
struct ModelCatalogFieldsTests {
    private func cloud(_ body: String) throws -> CloudInfo {
        let json = ##"{"data":[{"id":"vendor/x","name":"X",\##(body)}]}"##
        let all = try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8)).descriptors(usable: true)
        let model = try #require(all.first)
        return try #require(model.cloud)
    }

    @Test func providerCutoffUpstreamsAndMaxOutputAreRead() throws {
        let info = try cloud(##""provider":"Vendor","knowledge_cutoff":"2025-06","providers":["a","b"],"top_provider":{"max_completion_tokens":4096}"##)
        #expect(info.providerName == "Vendor")
        #expect(info.knowledgeCutoff == "2025-06")
        #expect(info.upstreamNames == ["a", "b"])
        #expect(info.maxOutputTokens == 4096)
    }

    @Test func absentFieldsStayNil() throws {
        let info = try cloud(##""top_provider":{"max_completion_tokens":null},"knowledge_cutoff":null"##)
        #expect(info.providerName == nil)
        #expect(info.knowledgeCutoff == nil)
        #expect(info.upstreamNames == nil)
        #expect(info.maxOutputTokens == nil)
    }

    @Test func aFieldOfTheWrongShapeIsIgnoredAndTheListStillDecodes() throws {
        let info = try cloud(##""provider":{"name":"x"},"knowledge_cutoff":2025,"top_provider":{"max_completion_tokens":"8192"}"##)
        #expect(info.providerName == nil)
        #expect(info.knowledgeCutoff == nil)
        #expect(info.maxOutputTokens == 8192, "numbers sent as text still read")
    }

    @Test func aReasoningTagMeansTheModelReasons() throws {
        #expect(try cloud(##""capabilities":["chat","reasoning"],"supported_parameters":["max_tokens"]"##).supportsReasoning)
        #expect(try !cloud(##""capabilities":["chat"],"supported_parameters":["max_tokens"]"##).supportsReasoning)
    }
}
