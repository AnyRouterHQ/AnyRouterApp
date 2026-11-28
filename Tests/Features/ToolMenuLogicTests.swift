import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct ToolMenuLogicTests {
    private let custom = MCPServer(id: "c1", name: "Deploys", url: URL(string: "https://example.com/mcp")!, auth: .bearerToken)

    private func tool(_ name: String, _ source: RegisteredTool.Source, on: Bool = true) -> RegisteredTool {
        let id: String
        switch source {
        case .builtIn: id = "builtin/\(name)"
        case .mcp(let serverID, _): id = IntegrationsLogic.toolKey(serverID: serverID, toolName: name)
        }
        return RegisteredTool(id: id, source: source, name: name, title: name.uppercased(), description: "",
                              schema: "{}", needsApproval: false, enabled: on)
    }

    @Test func sourcesFallIntoDeviceAnyRouterAndCustomSubmenus() {
        let sources = [ToolSourceCatalog.device, ToolSourceCatalog.exa, ToolSourceCatalog.deepWiki,
                       ToolSourceCatalog.anyRouter, ToolSourceCatalog.custom(custom)]
        let tools = [
            tool("fetch_url", .builtIn), tool("calculator", .builtIn, on: false), tool("web_search", .builtIn),
            tool("web_search_exa", .mcp(serverID: "exa", serverName: "Exa")),
            tool("ask_wiki_question", .mcp(serverID: "deepwiki", serverName: "DeepWiki")),
            tool("get_credits", .mcp(serverID: "anyrouter", serverName: "AnyRouter")),
            tool("deploy", .mcp(serverID: "c1", serverName: "Deploys")),
        ]
        let groups = ToolMenuLogic.groups(sources: sources, tools: tools) { $0.id != "deepwiki" }

        #expect(groups.map(\.id) == ["device", "anyrouter", "c1"])
        #expect(groups.map(\.title) == ["On this device", "AnyRouter", "Deploys"])
        #expect(groups[1].icon == ToolSourceCatalog.anyRouter.icon, "the web services sit under AnyRouter's mark")
        #expect(groups[1].sources.map(\.id) == ["anyrouter", "exa", "deepwiki"], "AnyRouter's own tools come first")
        #expect(groups[0].sources[0].tools.map(\.id) == ["builtin/fetch_url", "builtin/calculator"], "web_search is not the device's")
        #expect(groups[1].sources[0].tools.map(\.title) == ["WEB_SEARCH", "GET_CREDITS"])
        #expect(groups[2].sources[0].tools.map(\.id) == ["c1/deploy"])

        #expect(groups.map(\.onCount) == [1, 3, 1], "a tool that is off, or whose source is off, is not counted")
        #expect(ToolMenuLogic.summary(chatOn: true, groups: groups) == "5 on")
        #expect(ToolMenuLogic.summary(chatOn: false, groups: groups) == "Off")
        #expect(ToolMenuLogic.countText(0) == "0 on")
    }

    @Test func aWebServiceAloneStillOpensItsOwnAnyRouterSubmenu() {
        let groups = ToolMenuLogic.groups(sources: [ToolSourceCatalog.exa], tools: []) { _ in true }
        #expect(groups.map(\.id) == ["anyrouter"])
        #expect(groups[0].sources.map(\.id) == ["exa"])
        #expect(groups[0].onCount == 0)
    }

    private func registry() -> ToolRegistry {
        let defaults = testDefaults()
        let integrations = IntegrationsStore(defaults: defaults, credentials: FakeCredentialStore(),
                                             anyRouterToken: { "tok" }, session: MCPStubProtocol.session())
        return ToolRegistry(integrations: integrations, publicSources: ToolSourceCatalog.publicSources, defaults: defaults)
    }

    private func groups(_ registry: ToolRegistry, for model: ModelSource) -> [ToolMenuGroup] {
        ToolMenuLogic.groups(sources: registry.menuSources, tools: registry.tools) { registry.isOn($0, modelSource: model) }
    }

    /// Signed in, Apple's model searches with Exa and a cloud model searches with AnyRouter, so Exa's switch differs.
    @Test func theSwitchesFollowTheChatsModelAndTheSignIn() async {
        serveSearchServer()
        let registry = registry()
        let signedOut = groups(registry, for: .anyrouter)
        #expect(!signedOut[1].sources.contains { $0.id == "anyrouter" }, "AnyRouter's tools wait for a sign-in")
        #expect(signedOut[1].sources.first { $0.id == "exa" }?.isOn == true)

        await registry.integrations.accountChanged(signedIn: true)?.value
        let cloud = groups(registry, for: .anyrouter)
        let apple = groups(registry, for: .apple)
        #expect(cloud[1].sources.first?.id == "anyrouter")
        #expect(cloud[1].sources.first { $0.id == "exa" }?.isOn == false, "a cloud model searches with AnyRouter")
        #expect(apple[1].sources.first { $0.id == "exa" }?.isOn == true, "Apple's model cannot use AnyRouter search")
        #expect(cloud[0].sources[0].tools.map(\.id).contains("builtin/ocr_image"))

        registry.setTool("anyrouter/get_credits", on: false)
        #expect(groups(registry, for: .anyrouter)[1].sources[0].tools.first { $0.id == "anyrouter/get_credits" }?.isOn == false,
                "a live MCP tool switches off from the menu too")
    }

    @Test func aToolSwitchInTheMenuIsTheSameSwitchAsInSettings() throws {
        let registry = registry()
        registry.setTool("builtin/calculator", on: false)
        #expect(!registry.isBuiltInEnabled("calculator"))
        registry.setTool("builtin/calculator", on: true)
        #expect(registry.isBuiltInEnabled("calculator"))

        let exa = ToolSourceCatalog.exa
        let fetch = try #require(exa.tools.first { $0.name == "web_fetch_exa" })
        let key = IntegrationsLogic.toolKey(serverID: "exa", toolName: "web_fetch_exa")
        let before = registry.integrations.isEnabled(fetch.mcpTool, on: exa.server!)
        registry.setTool(key, on: !before)
        #expect(registry.integrations.isEnabled(fetch.mcpTool, on: exa.server!) == !before)
        #expect(registry.tools.first { $0.id == key }?.enabled == !before)
        registry.setTool("nothing/here", on: false)
    }
}
