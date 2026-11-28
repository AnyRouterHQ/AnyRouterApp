import Foundation
import Testing

@testable import AnyRouter

struct ToolSourceCatalogTests {
    private let allSources = [ToolSourceCatalog.device] + ToolSourceCatalog.publicSources + [ToolSourceCatalog.anyRouter]

    @Test func everySourceHasItsOwnIdAndAnIcon() {
        #expect(Set(allSources.map(\.id)).count == allSources.count)
        #expect(allSources.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty })
    }

    /// A public service never gets a token: no account, no key, and the app names who receives the text.
    @Test func publicSourcesNeedNoAccountAndNameTheirRecipient() {
        #expect(ToolSourceCatalog.publicSources.map(\.id) == ["exa", "deepwiki", "mslearn"])
        for source in ToolSourceCatalog.publicSources {
            #expect(source.group == .web)
            #expect(source.auth == .none)
            #expect(!source.requiresSignIn)
            #expect(source.server?.auth == MCPServer.Auth.none)
            #expect(source.server?.url.scheme == "https")
            #expect(source.recipient != nil)
            #expect(!source.tools.isEmpty)
            #expect(source.server?.isCurated == true)
        }
        #expect(ToolSourceCatalog.anyRouter.requiresSignIn)
    }

    @Test func exaStartsOnWhenAnyRouterCannotSearchForTheChat() {
        let table: [(signedIn: Bool, model: ModelSource?, on: Bool)] = [
            (false, nil, true), (false, .anyrouter, true), (false, .apple, true),
            (true, .anyrouter, false), (true, nil, false),
            (true, .apple, true), (true, .gguf, true), (true, .mlx, true),
        ]
        for row in table {
            let situation = ToolSituation(signedIn: row.signedIn, modelSource: row.model)
            #expect(ToolSourceCatalog.exa.isOnByDefault(in: situation) == row.on, "\(row)")
        }
    }

    /// Tools are on out of the box: a new person gets the device tools and the no-account services without a trip to Settings.
    @Test func everyOtherSourceStartsOn() {
        for signedIn in [true, false] {
            let situation = ToolSituation(signedIn: signedIn, modelSource: .apple)
            #expect(ToolSourceCatalog.deepWiki.isOnByDefault(in: situation))
            #expect(ToolSourceCatalog.microsoftLearn.isOnByDefault(in: situation))
            #expect(ToolSourceCatalog.device.isOnByDefault(in: situation))
            #expect(ToolSourceCatalog.anyRouter.isOnByDefault(in: situation))
        }
    }

    @Test func eachPinnedToolIsReadOnlyAndHasAValidSchema() throws {
        for source in ToolSourceCatalog.publicSources {
            for pin in source.tools {
                let schema = try #require(JSONValue.parse(pin.schema.json))
                #expect(schema["type"]?.string == "object", "\(pin.name)")
                #expect(pin.mcpTool.isReadOnly)
                #expect(source.server?.skipsApproval(pin.mcpTool) == true, "\(pin.name) runs without a question")
                #expect(pin.summary.count <= 80, "\(pin.name) stays short for a small model")
            }
        }
    }

    @Test func smallToolListsStartWithOneToolForGithubAndDocs() {
        let defaults = { (source: ToolSource) in source.tools.filter(\.onByDefault).map(\.name) }
        #expect(defaults(ToolSourceCatalog.exa) == ["web_search_exa", "web_fetch_exa"])
        #expect(defaults(ToolSourceCatalog.deepWiki) == ["ask_wiki_question"])
        #expect(defaults(ToolSourceCatalog.microsoftLearn) == ["microsoft_docs_search", "microsoft_docs_fetch"])
    }

    @Test func aToolTheAppDoesNotKnowOnAPublicServerStartsOff() throws {
        let exa = try #require(ToolSourceCatalog.exa.server)
        #expect(!exa.enabledByDefault(MCPTool(name: "agent_run")))
        #expect(exa.enabledByDefault(MCPTool(name: "web_search_exa")))
    }

    @Test func aCustomServerNeverSkipsApprovalEvenIfItClaimsReadOnly() {
        let custom = MCPServer(id: "c", name: "C", url: URL(string: "https://example.com/mcp")!, auth: .none)
        let claimed = MCPTool(name: "web_search_exa", annotations: .init(readOnlyHint: true))
        #expect(!custom.isCurated)
        #expect(!custom.skipsApproval(claimed))
    }

    @Test func completingFillsWhatASmallModelLeavesOut() {
        let given: JSONValue = .object(["query": .string("swift")])
        let filled = ToolSourceCatalog.completing(given, serverID: "exa", tool: "web_search_exa")
        #expect(filled == .object(["query": .string("swift"), "numResults": .number(5), "objective": .string("swift")]))

        let own: JSONValue = .object(["query": .string("a"), "numResults": .number(2), "objective": .string("b")])
        #expect(ToolSourceCatalog.completing(own, serverID: "exa", tool: "web_search_exa") == own)
        #expect(ToolSourceCatalog.completing(given, serverID: "exa", tool: "web_fetch_exa") == given)
        #expect(ToolSourceCatalog.completing(given, serverID: "other", tool: "web_search_exa") == given)
        let notAnObject: JSONValue = .string("x")
        #expect(ToolSourceCatalog.completing(notAnObject, serverID: "exa", tool: "web_search_exa") == notAnObject)
    }

    @Test func searchToolsNameTheArgumentThatCarriesSearchWords() {
        #expect(ToolSourceCatalog.queryArgument(forTool: "web_search") == "query")
        #expect(ToolSourceCatalog.queryArgument(forTool: "web_search_exa") == "query")
        #expect(ToolSourceCatalog.queryArgument(forTool: "ask_wiki_question") == "question")
        #expect(ToolSourceCatalog.queryArgument(forTool: "web_fetch_exa") == nil)
        #expect(ToolSourceCatalog.queryArgument(forTool: "calculator") == nil)
    }

    @Test func everyToolGetsAnIcon() {
        #expect(ToolSourceCatalog.symbol(forTool: "fetch_url") == "arrow.down.doc")
        #expect(ToolSourceCatalog.symbol(forTool: "current_date_time") == "calendar")
        #expect(ToolSourceCatalog.symbol(forTool: "firecrawl__firecrawl_search") == "magnifyingglass")
        #expect(ToolSourceCatalog.symbol(forTool: "list_models") == "cpu")
        #expect(ToolSourceCatalog.symbol(forTool: "zzz") == "wrench.and.screwdriver")
    }

    @Test func aCustomServerBecomesASourceInItsOwnGroup() {
        let server = MCPServer(id: "x", name: "Mine", url: URL(string: "https://tools.example.com/mcp")!, auth: .bearerToken)
        let source = ToolSourceCatalog.custom(server)
        #expect(source.group == .custom)
        #expect(source.subtitle == "tools.example.com")
        #expect(source.isOnByDefault(in: ToolSituation(signedIn: false, modelSource: nil)))
        #expect(!source.requiresSignIn)
    }
}
