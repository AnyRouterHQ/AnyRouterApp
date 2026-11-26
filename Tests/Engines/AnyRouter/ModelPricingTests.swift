import Foundation
import Testing
@testable import AnyRouter

/// The catalog sends prices as strings and numbers, per 1M tokens. Parsed once at the boundary.
struct ModelPricingTests {
    private let json = """
        {"data":[
         {"id":"anthropic/claude-sonnet-4-6","name":"Claude Sonnet 4.6","category":"text","context_length":1000000,
          "capabilities":["chat","function-calling"],"created":1771286400,
          "providers":["anthropic-byok","anthropic-vertex-byok"],
          "architecture":{"input_modalities":["text","image","file"],"output_modalities":["text"]},
          "supported_parameters":["max_tokens","tools","reasoning"],
          "pricing":{"prompt":"3","completion":"15","input_per_1m":3,"output_per_1m":15,
                     "input_cache_read":"0.3","input_cache_read_per_1m":0.3,"billing":"byok"},
          "can_route":false,"can_route_reason":"needs_key"},
         {"id":"anyrouter/auto","name":"AnyRouter Auto","category":"text","context_length":4194304,
          "capabilities":["chat","vision"],"providers":["AnyRouter"],
          "members":[{"id":"a"},{"id":"b"},{"id":"c"}],
          "pricing":{"prompt":"0","completion":"0","input_per_1m":0,"output_per_1m":0,"billing":"free"},
          "can_route":true},
         {"id":"vendor/cheap","name":"Cheap","category":"text","context_length":8192,
          "pricing":{"prompt":"0.15","completion":"0.6","billing":"credits"},"can_route":null},
         {"id":"vendor/off","name":"Off","category":"text","pricing":{"billing":"credits"},
          "can_route":false,"can_route_reason":"disabled"},
         {"id":"vendor/none","name":"None","category":"text","pricing":{"billing":"credits"},
          "can_route":false,"can_route_reason":"no_route"}
        ]}
        """

    private func models(usable: Bool = true) throws -> [String: ModelDescriptor] {
        let response = try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8))
        return Dictionary(uniqueKeysWithValues: response.descriptors(usable: usable).map { ($0.wireID, $0) })
    }

    @Test func numberedPricesWinAndStringsAreTheFallback() throws {
        let all = try models()
        let sonnet = try #require(all["anthropic/claude-sonnet-4-6"]?.cloud)
        #expect(sonnet.pricing.input == 3)
        #expect(sonnet.pricing.output == 15)
        #expect(sonnet.pricing.cacheRead == Decimal(string: "0.3"))
        #expect(sonnet.pricing.billing == .byok)
        // No per-1M numbers: the string fields are per 1M too.
        let cheap = try #require(all["vendor/cheap"]?.cloud)
        #expect(cheap.pricing.input == Decimal(string: "0.15"))
        #expect(cheap.pricing.output == Decimal(string: "0.6"))
    }

    @Test func routingMapsToAvailability() throws {
        let all = try models()
        #expect(all["anthropic/claude-sonnet-4-6"]?.cloud?.availability == .needsKey)
        #expect(all["anyrouter/auto"]?.cloud?.availability == .usable)
        #expect(all["vendor/cheap"]?.cloud?.availability == .usable) // null means unknown, so usable
        #expect(all["vendor/off"]?.cloud?.availability == .disabled)
        #expect(all["vendor/none"]?.cloud?.availability == .noRoute)
    }

    @Test func aModelIsInstalledOnlyWhenSignedInAndRoutable() throws {
        let signedIn = try models(usable: true)
        #expect(signedIn["anyrouter/auto"]?.isInstalled == true)
        #expect(signedIn["anthropic/claude-sonnet-4-6"]?.isInstalled == false)
        let signedOut = try models(usable: false)
        #expect(signedOut["anyrouter/auto"]?.isInstalled == false)
    }

    @Test func countsFlagsAndDateComeFromTheCatalog() throws {
        let all = try models()
        let sonnet = try #require(all["anthropic/claude-sonnet-4-6"]?.cloud)
        #expect(sonnet.upstreamCount == 2)
        #expect(sonnet.memberCount == nil)
        #expect(sonnet.supportsVision) // image input
        #expect(sonnet.supportsReasoning)
        #expect(sonnet.created == Date(timeIntervalSince1970: 1_771_286_400))
        let auto = try #require(all["anyrouter/auto"]?.cloud)
        #expect(auto.memberCount == 3)
        #expect(auto.supportsVision) // capability tag
        #expect(!auto.supportsReasoning)
    }

    @Test func aMissingPriceStaysUnknownInsteadOfFree() throws {
        let off = try #require(models()["vendor/off"]?.cloud)
        #expect(off.pricing.input == nil)
        #expect(!off.pricing.isFree)
    }

    @Test func descriptorsWithoutCloudInfoStillDecode() throws {
        let old = #"{"id":"a","source":"apple","displayName":"A","capabilities":["chat"],"isInstalled":true}"#
        #expect(try JSONDecoder().decode(ModelDescriptor.self, from: Data(old.utf8)).cloud == nil)
    }

    @Test func cloudInfoRoundTripsThroughJSON() throws {
        let model = cloudModel("openai/gpt-5", input: Decimal(string: "1.25"), output: 10, vision: true)
        let back = try JSONDecoder().decode(ModelDescriptor.self, from: JSONEncoder().encode(model))
        #expect(back == model)
    }
}
