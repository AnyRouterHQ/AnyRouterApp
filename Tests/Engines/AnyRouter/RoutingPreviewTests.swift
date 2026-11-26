import Foundation
import Testing
@testable import AnyRouter

struct RoutingPreviewTests {
    // Trimmed from the real response of GET /models/anyrouter/auto/routing-preview.
    private let json = """
        {"model":"anyrouter/auto","has_byok":false,"resolved":[
         {"id":"reflection/beam-1.0","name":"Beam 1.0","provider":"reflection","context_length":1048576,
          "max_output":131072,"rank":0,"input_price_per_1m":0,"output_price_per_1m":0,"byok_only":false},
         {"id":"openai/gpt-5.6-luna","name":"GPT-5.6 Luna","provider":"OpenAI","context_length":1050000,
          "rank":38.1,"input_price_per_1m":0.2,"output_price_per_1m":1.2}]}
        """

    @Test func membersKeepTheFailoverOrderAndPrices() throws {
        let members = try JSONDecoder().decode(AnyRouterRoutingPreview.Response.self, from: Data(json.utf8)).members
        #expect(members.map(\.id) == ["reflection/beam-1.0", "openai/gpt-5.6-luna"])
        #expect(members[1].name == "GPT-5.6 Luna")
        #expect(members[1].inputPer1M == Decimal(string: "0.2"))
        #expect(members[1].outputPer1M == Decimal(string: "1.2"))
        #expect(members[0].inputPer1M == 0)
    }

    @Test func eachMemberReadsAsProviderPriceAndContext() throws {
        let members = try JSONDecoder().decode(AnyRouterRoutingPreview.Response.self, from: Data(json.utf8)).members
        #expect(RouterDetailLogic.detail(members[0]) == "reflection · Free · 1M ctx")
        #expect(RouterDetailLogic.detail(members[1]) == "OpenAI · $0.2 / $1.2 per 1M · 1M ctx")
    }

    @Test func aMemberWithoutAPriceOrNameStillShows() throws {
        let members = try JSONDecoder().decode(
            AnyRouterRoutingPreview.Response.self, from: Data(#"{"resolved":[{"id":"x/y"}]}"#.utf8)).members
        #expect(members.first?.name == "x/y")
        #expect(RouterDetailLogic.detail(members[0]).isEmpty)
    }
}
