import Foundation
import Testing
@testable import AnyRouter

/// The detail screen's fields, mapped from a recorded `GET /api/v1/models` answer.
/// `Tests/Fixtures/anyrouter-models.json` holds three real entries (a paid model, a free one and the auto router),
/// without their per-upstream lists, and with the router's members cut to three.
struct ModelDetailLogicTests {
    private func recorded() throws -> [String: ModelDescriptor] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/anyrouter-models.json"))
        let response = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return Dictionary(uniqueKeysWithValues: response.descriptors(usable: true).map { ($0.wireID, $0) })
    }

    private func detail(_ wire: String, usage: ModelUsage? = nil) throws -> ModelDetail {
        let all = try recorded()
        let model = try #require(all[wire])
        return ModelDetailLogic.make(model, usage: usage)
    }

    private func values(_ fields: [ModelDetail.Field]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.label, $0.value) })
    }

    @Test func aPaidModelListsItsDescriptionOverviewAndFullPricing() throws {
        let d = try detail("openai/gpt-6.2-sol")
        #expect(d.description?.hasPrefix("GPT-6.2 Sol is OpenAI's efficient model") == true)
        #expect(d.overview.map(\.label) == ["ID", "Provider", "Context window", "Max output", "Released"])
        let overview = values(d.overview)
        #expect(overview["ID"] == "openai/gpt-6.2-sol")
        #expect(overview["Provider"] == "OpenAI")
        #expect(overview["Context window"] == "1,050,000 tokens")
        #expect(overview["Max output"] == "128,000 tokens")
        #expect(overview["Released"] == "Nov 17, 2026")
        #expect(d.pricing.map(\.label) == ["Billing", "Input", "Output", "Cached input"])
        let pricing = values(d.pricing)
        #expect(pricing["Billing"] == "AnyRouter credits")
        #expect(pricing["Input"] == "$0.4 per 1M tokens")
        #expect(pricing["Output"] == "$2 per 1M tokens")
        #expect(pricing["Cached input"] == "$0.02 per 1M tokens")
    }

    @Test func capabilitiesComeFromTheCatalogTags() throws {
        #expect(try detail("openai/gpt-6.2-sol").capabilities == [.vision, .reasoning, .tools])
        #expect(try detail("nvidia/nemotron-3.5-bolt-e4b").capabilities == [.reasoning, .tools])
    }

    @Test func upstreamProvidersAreListedByCatalogName() throws {
        let d = try detail("openai/gpt-6.2-sol")
        #expect(d.upstreams.count == 27)
        #expect(d.upstreams.first == "openai-byok")
        #expect(try detail("nvidia/nemotron-3.5-bolt-e4b").upstreams == ["nvidia", "nvidia-byok"])
    }

    @Test func aFreeModelHasOnePriceLineAndNoMaxOutputWhenTheCatalogHasNone() throws {
        let d = try detail("nvidia/nemotron-3.5-bolt-e4b")
        #expect(d.pricing == [ModelDetail.Field(label: "Price", value: "Free")])
        #expect(!d.overview.contains { $0.label == "Max output" })
        #expect(values(d.overview)["Context window"] == "65,536 tokens")
    }

    @Test func aRouterSaysHowManyModelsItRoutesTo() throws {
        let d = try detail("anyrouter/auto")
        #expect(values(d.overview)["Routes to"] == "3 models")
        #expect(values(d.overview)["Provider"] == "anyrouter")
        #expect(d.pricing == [ModelDetail.Field(label: "Price", value: "Free")])
    }

    @Test func linksPointAtTheModelPageAndTheCatalogEntry() throws {
        let d = try detail("openai/gpt-6.2-sol")
        #expect(d.pageURL.absoluteString == "https://anyrouter.dev/model/openai/gpt-6.2-sol")
        #expect(d.apiURL.absoluteString == "https://anyrouter.dev/api/v1/models/openai/gpt-6.2-sol")
        #expect(d.wireID == "openai/gpt-6.2-sol")
    }

    @Test func weeklyUsageAddsRankTokensAndRequests() throws {
        #expect(try detail("openai/gpt-6.2-sol").usage.isEmpty)
        let usage = ModelUsage(id: "openai/gpt-6.2-sol", rank: 1, tokens: 12_345_678_901, requests: 53_975)
        let d = try detail("openai/gpt-6.2-sol", usage: usage)
        #expect(d.usage == [
            ModelDetail.Field(label: "Rank", value: "#1"),
            ModelDetail.Field(label: "Tokens", value: "12.3B"),
            ModelDetail.Field(label: "Requests", value: "54K"),
        ])
    }

    @Test func aKnowledgeCutoffShowsWhenTheCatalogStatesOne() {
        var model = cloudModel("vendor/x", summary: "  A model.  ")
        model.cloud?.knowledgeCutoff = "2025-06"
        let d = ModelDetailLogic.make(model, usage: nil)
        #expect(values(d.overview)["Knowledge cutoff"] == "2025-06")
        #expect(d.description == "A model.")
        model.cloud?.knowledgeCutoff = "  "
        #expect(values(ModelDetailLogic.make(model, usage: nil).overview)["Knowledge cutoff"] == nil)
    }

    @Test func aBlankDescriptionAndProviderFallBackToWhatIsKnown() {
        var model = cloudModel("vendor/x", summary: "   ")
        model.cloud?.providerName = " "
        let d = ModelDetailLogic.make(model, usage: nil)
        #expect(d.description == nil)
        #expect(values(d.overview)["Provider"] == "vendor")
        #expect(d.upstreams.isEmpty)
    }

    @Test func billingIsNamedForCreditsAndOwnKeysAndLeftOutWhenUnknown() {
        func pricing(_ billing: CloudBilling) -> [ModelDetail.Field] {
            ModelDetailLogic.make(cloudModel("vendor/x", input: 1, output: 2, billing: billing), usage: nil).pricing
        }
        #expect(pricing(.byok).first == ModelDetail.Field(label: "Billing", value: "Your provider key"))
        #expect(pricing(.unknown).map(\.label) == ["Input", "Output"])
        #expect(pricing(.credits).map(\.label) == ["Billing", "Input", "Output"])
    }

    @Test func aMissingPriceIsLeftOutInsteadOfShownAsFree() {
        let d = ModelDetailLogic.make(cloudModel("vendor/x", input: nil, output: nil, billing: .credits), usage: nil)
        #expect(d.pricing == [ModelDetail.Field(label: "Billing", value: "AnyRouter credits")])
    }

    @Test func aLocalModelHasNoPricingUpstreamsOrProvider() {
        let d = ModelDetailLogic.make(localModel("gguf/o/r/f-Q4_K_M.gguf"), usage: nil)
        #expect(d.pricing.isEmpty)
        #expect(d.upstreams.isEmpty)
        #expect(d.overview.map(\.label) == ["ID"])
    }
}
