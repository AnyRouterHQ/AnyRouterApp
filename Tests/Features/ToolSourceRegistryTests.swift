import XCTest

@testable import AnyRouter

private final class ScriptedConsent: ToolApproving, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [ToolApprovalRequest] = []
    var requests: [ToolApprovalRequest] { lock.withLock { asked } }
    /// A first-use note is accepted for good; any other question is refused.
    func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
        lock.withLock { asked.append(request) }
        return request.canRemember ? .alwaysAllow : .deny
    }
}

private struct Refuses: ToolApproving {
    func decide(_ request: ToolApprovalRequest) async -> ToolDecision { .deny }
}

@MainActor
final class ToolSourceRegistryTests: XCTestCase {
    /// `token` is the AnyRouter sign-in token. It is nil unless a test checks that it never reaches a public server.
    private func makeRegistry(signedIn: Bool = false, defaults: UserDefaults? = nil, token: String? = nil) -> ToolRegistry {
        let defaults = defaults ?? testDefaults()
        let integrations = IntegrationsStore(
            defaults: defaults, credentials: FakeCredentialStore(),
            anyRouterToken: { token }, session: MCPStubProtocol.session())
        if signedIn { integrations.accountChanged(signedIn: true) }
        return ToolRegistry(integrations: integrations, publicSources: ToolSourceCatalog.publicSources, defaults: defaults)
    }

    private func names(_ registry: ToolRegistry, _ source: ModelSource?) -> [String]? {
        registry.makeHost(approver: Refuses(), context: ToolContext(modelSource: source))?.specs.map(\.name)
    }

    private let device = ["fetch_url", "current_date_time", "calculator"]
    private let exa = ["web_search_exa", "web_fetch_exa"]
    /// The main tool of DeepWiki and of Microsoft Learn, on out of the box.
    private let docs = ["ask_wiki_question", "microsoft_docs_search", "microsoft_docs_fetch"]
    /// Apple's model gets four tools: the clock, the calculator, search and one page reader.
    private let apple = ["current_date_time", "calculator", "web_search_exa", "fetch_url"]

    // MARK: Defaults per sign-in state and model source

    func testSignedOutStartsWithDeviceToolsExaAndTheDocsServicesForEveryModel() {
        let registry = makeRegistry()
        XCTAssertEqual(names(registry, .anyrouter), device + exa + docs)
        for source in [ModelSource.gguf, .mlx, .apple] {
            XCTAssertEqual(names(registry, source), apple, "\(source) gets the four a small context holds")
        }
        XCTAssertEqual(names(registry, nil), device + exa + docs)
    }

    func testSignedInOnACloudModelLeavesWebSearchToAnyRouter() {
        let registry = makeRegistry(signedIn: true)
        XCTAssertEqual(names(registry, .anyrouter), device + docs)
        XCTAssertEqual(names(registry, nil), device + docs)
    }

    func testSignedInOnADeviceModelStillGetsExa() {
        let registry = makeRegistry(signedIn: true)
        for source in [ModelSource.gguf, .mlx, .apple] {
            XCTAssertEqual(names(registry, source), apple, "\(source)")
        }
    }

    func testOtherPublicServicesStartOnWithOnlyTheirMainTool() {
        let registry = makeRegistry()
        let deepWiki = ToolSourceCatalog.deepWiki
        let learn = ["microsoft_docs_search", "microsoft_docs_fetch"]
        XCTAssertTrue(registry.isOn(deepWiki))
        XCTAssertTrue(registry.isOn(ToolSourceCatalog.microsoftLearn))
        let server = deepWiki.server!
        let structure = deepWiki.tools[1].mcpTool
        registry.integrations.setEnabled(true, tool: structure, on: server)
        XCTAssertEqual(names(registry, .anyrouter), device + exa + ["ask_wiki_question", "read_wiki_structure"] + learn)
        let ask = deepWiki.tools[0].mcpTool
        registry.integrations.setEnabled(false, tool: ask, on: server)
        XCTAssertEqual(names(registry, .anyrouter), device + exa + ["read_wiki_structure"] + learn)
    }

    /// The defaults moved from off to on. Only a switch someone flipped is stored, so an install from before the move
    /// gets the new defaults for everything it never touched, and keeps every switch it did.
    func testAnInstallFromBeforeToolsWereOnKeepsItsChoicesAndGetsTheRest() {
        let defaults = testDefaults()
        defaults.set(["mslearn": false, "device": true], forKey: "tools.sourceChoices")
        defaults.set(["calculator"], forKey: "tools.disabledBuiltIns")
        let registry = makeRegistry(defaults: defaults)
        XCTAssertTrue(registry.isOn(ToolSourceCatalog.deepWiki), "never chosen, so it follows the new default")
        XCTAssertFalse(registry.isOn(ToolSourceCatalog.microsoftLearn), "turned off by the person, so it stays off")
        XCTAssertEqual(names(registry, .anyrouter), ["fetch_url", "current_date_time"] + exa + ["ask_wiki_question"])
    }

    // MARK: Named with @

    private func forcedNames(_ registry: ToolRegistry, _ ids: Set<String>, _ source: ModelSource? = .anyrouter) -> [String]? {
        registry.makeHost(approver: Refuses(), context: ToolContext(modelSource: source, forcedSourceIDs: ids))?.specs.map(\.name)
    }

    func testANamedSourceIsTheOnlyOneOfferedAndIgnoresItsSwitch() {
        let registry = makeRegistry()
        XCTAssertEqual(forcedNames(registry, ["exa"]), exa)
        registry.setSource(ToolSourceCatalog.exa, on: false)
        XCTAssertEqual(forcedNames(registry, ["exa"]), exa, "named, so on for this message")
        XCTAssertEqual(names(registry, .anyrouter), device + docs, "the switch still decides the other messages")
    }

    func testANamedSourceKeepsItsOwnToolSwitches() {
        let registry = makeRegistry()
        XCTAssertEqual(forcedNames(registry, ["deepwiki"]), ["ask_wiki_question"])
        XCTAssertEqual(forcedNames(registry, ["deepwiki", "mslearn"]), ["ask_wiki_question", "microsoft_docs_search", "microsoft_docs_fetch"])
    }

    func testNamingTheDeviceOffersOnlyItsTools() {
        let registry = makeRegistry()
        XCTAssertEqual(forcedNames(registry, ["device"]), device)
    }

    func testNamingASourceWithNothingConnectedOffersNothing() {
        XCTAssertNil(forcedNames(makeRegistry(), ["anyrouter"]))
    }

    // MARK: Search for models without tools

    func testALocalModelCanHaveASearchRunWhenExaIsOn() {
        let registry = makeRegistry()
        XCTAssertTrue(registry.canPreSearch(modelSource: .gguf))
        XCTAssertTrue(registry.canPreSearch(modelSource: .mlx))
        XCTAssertTrue(makeRegistry(signedIn: true).canPreSearch(modelSource: .gguf), "a device model has no AnyRouter search")

        registry.setSource(ToolSourceCatalog.exa, on: false)
        XCTAssertFalse(registry.canPreSearch(modelSource: .gguf))

        let toolOff = makeRegistry()
        toolOff.integrations.setEnabled(false, tool: ToolSourceCatalog.exa.tools[0].mcpTool, on: ToolSourceCatalog.exa.server!)
        XCTAssertFalse(toolOff.canPreSearch(modelSource: .gguf), "the search tool itself is switched off")

        let none = ToolRegistry(
            integrations: makeRegistry().integrations, publicSources: [], defaults: testDefaults())
        XCTAssertFalse(none.canPreSearch(modelSource: .gguf))
    }

    func testPreSearchGoesThroughTheSameHostSoTheFirstUseNoteAndTheTokenRuleApply() async throws {
        serveExa()
        let registry = makeRegistry(token: "tok-secret")
        let approver = ScriptedConsent()
        let context = ToolContext(userTexts: ["latest swift news"], modelSource: .gguf)
        let answer = await registry.preSearch(query: "latest swift news", approver: approver, context: context)
        let result = try XCTUnwrap(answer)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(WebGrounding.parse(result.text).first?.title, "Swift Programming Language")

        let note = try XCTUnwrap(approver.requests.first)
        XCTAssertTrue(note.canRemember)
        XCTAssertEqual(note.serverName, "Exa")

        let url = try XCTUnwrap(ToolSourceCatalog.exa.server?.url)
        let sent = MCPStubProtocol.requests(for: url)
        XCTAssertTrue(sent.allSatisfy { $0.header("Authorization") == nil })
        let call = try XCTUnwrap(sent.first { $0.rpcMethod == "tools/call" })
        XCTAssertEqual(call.body?["params"]?["name"]?.string, "web_search_exa")
        XCTAssertEqual(call.body?["params"]?["arguments"]?["query"]?.string, "latest swift news")
    }

    func testRefusingTheFirstUseNoteGivesAFailedAnswerAndSendsNothing() async throws {
        serveExa()
        let registry = makeRegistry()
        let answer = await registry.preSearch(
            query: "latest swift news", approver: Refuses(), context: ToolContext(modelSource: .gguf))
        let result = try XCTUnwrap(answer)
        XCTAssertTrue(result.isError)
        let url = try XCTUnwrap(ToolSourceCatalog.exa.server?.url)
        XCTAssertFalse(MCPStubProtocol.requests(for: url).contains { $0.rpcMethod == "tools/call" })
    }

    func testPreSearchRunsNothingWhenSearchIsOffOrTheModelIsUnknown() async {
        let registry = makeRegistry()
        let none = await registry.preSearch(query: "q", approver: Refuses(), context: ToolContext())
        XCTAssertNil(none, "no model, no search")
        registry.setSource(ToolSourceCatalog.exa, on: false)
        let off = await registry.preSearch(query: "q", approver: Refuses(), context: ToolContext(modelSource: .gguf))
        XCTAssertNil(off)
    }

    // MARK: The user's choice

    func testAChoiceBeatsTheDefaultAndSurvivesARestart() {
        let defaults = testDefaults()
        let registry = makeRegistry(defaults: defaults)
        registry.setSource(ToolSourceCatalog.exa, on: false)
        XCTAssertEqual(names(registry, .anyrouter), device + docs)
        XCTAssertEqual(names(makeRegistry(defaults: defaults), .anyrouter), device + docs, "kept after a restart")

        let signedIn = makeRegistry(signedIn: true, defaults: testDefaults())
        signedIn.setSource(ToolSourceCatalog.exa, on: true)
        XCTAssertEqual(names(signedIn, .anyrouter), device + exa + docs)
    }

    func testTurningTheDeviceOffRemovesItsToolsOnly() {
        let registry = makeRegistry()
        registry.setSource(ToolSourceCatalog.device, on: false)
        XCTAssertEqual(names(registry, .anyrouter), exa + docs)
        for source in ToolSourceCatalog.publicSources { registry.setSource(source, on: false) }
        XCTAssertNil(names(registry, .apple))
    }

    func testSettingsAndTheComposerListTheSameSourcesInOrder() {
        let signedOut = makeRegistry()
        XCTAssertEqual(signedOut.sources.map(\.id), ["device", "exa", "deepwiki", "mslearn", "anyrouter"])
        XCTAssertEqual(signedOut.menuSources.map(\.id), ["device", "exa", "deepwiki", "mslearn"])
        XCTAssertEqual(makeRegistry(signedIn: true).menuSources.map(\.id), ["device", "exa", "deepwiki", "mslearn", "anyrouter"])
        XCTAssertEqual(
            Set(signedOut.sources.map(\.group)), Set(ToolSource.Group.allCases.filter { $0 != .custom }))
    }

    func testACustomServerIsASourceAndItsSwitchIsKept() throws {
        let registry = makeRegistry()
        let server = try registry.integrations.addServer(name: "Mine", urlString: "https://tools.example.com/mcp", token: "")
        let source = try XCTUnwrap(registry.sources.last)
        XCTAssertEqual(source.id, server.id)
        XCTAssertEqual(source.group, .custom)
        XCTAssertTrue(registry.isOn(source))
        registry.setSource(source, on: false)
        XCTAssertFalse(registry.isOn(source))
    }

    func testSettingsListsEveryPinnedToolWithItsSwitch() {
        let registry = makeRegistry()
        let listed = registry.tools.filter { $0.source != .builtIn }
        XCTAssertEqual(listed.map(\.name), [
            "web_search_exa", "web_fetch_exa", "ask_wiki_question", "read_wiki_structure", "read_wiki_contents",
            "microsoft_docs_search", "microsoft_docs_fetch", "microsoft_code_sample_search",
        ])
        XCTAssertEqual(listed.filter(\.enabled).map(\.name), [
            "web_search_exa", "web_fetch_exa", "ask_wiki_question", "microsoft_docs_search", "microsoft_docs_fetch",
        ])
        XCTAssertTrue(listed.allSatisfy { !$0.needsApproval })
    }

    // MARK: Small models

    func testLocalModelsAndAppleGetFourToolsWithShortDescriptions() {
        let registry = makeRegistry()
        for source in [ToolSourceCatalog.deepWiki, ToolSourceCatalog.microsoftLearn] {
            for pin in source.tools { registry.integrations.setEnabled(true, tool: pin.mcpTool, on: source.server!) }
        }
        let host = registry.makeHost(approver: Refuses(), context: ToolContext(modelSource: .gguf))!
        let list = host.specs.map(\.name)
        XCTAssertEqual(list, apple, "a docs search does not push the page reader out")
        XCTAssertTrue(host.specs.allSatisfy { $0.description.count <= 160 })

        let onApple = registry.makeHost(approver: Refuses(), context: ToolContext(modelSource: .apple))!
        XCTAssertEqual(onApple.specs.map(\.name), apple)

        let cloud = registry.makeHost(approver: Refuses(), context: ToolContext(modelSource: .anyrouter))!
        XCTAssertEqual(cloud.specs.count, 11, "a cloud model is offered every tool that is on")
    }

    // MARK: Exa against a recorded answer

    private func serveExa() {
        let initialize = exaFixture("exa-initialize"), list = exaFixture("exa-tools-list"), search = exaFixture("exa-search")
        MCPStubProtocol.register(host: "mcp.exa.ai") { request in
            switch request.rpcMethod {
            case "initialize": return recordedReply(initialize, to: request, headers: ["Mcp-Session-Id": "exa-sess"])
            case "notifications/initialized": return StubResponse(status: 202, headers: [:], body: "")
            case "tools/list": return recordedReply(list, to: request)
            case "tools/call": return recordedReply(search, to: request)
            default: return StubResponse(status: 400, body: "{}")
            }
        }
    }

    func testTheRecordedExaListParsesAndMatchesWhatTheAppPins() async throws {
        serveExa()
        let server = try XCTUnwrap(ToolSourceCatalog.exa.server)
        let client = MCPClient(server: server, token: { nil }, session: MCPStubProtocol.session())
        let info = try await client.connect()
        XCTAssertEqual(info.name, "exa-search-server")
        let tools = try await client.listTools()
        XCTAssertEqual(tools.map(\.name), ToolSourceCatalog.exa.tools.map(\.name))
        XCTAssertTrue(tools.allSatisfy(\.isReadOnly))
        let search = try XCTUnwrap(tools.first)
        XCTAssertEqual(search.inputSchema["properties"]?["query"]?["type"]?.string, "string")
    }

    func testExaSearchRunsWithNoTokenAfterOneFirstUseNote() async throws {
        serveExa()
        let registry = makeRegistry(token: "tok-secret")
        let approver = ScriptedConsent()
        let host = try XCTUnwrap(registry.makeHost(approver: approver, context: ToolContext(modelSource: .apple)))
        XCTAssertEqual(host.specs.first { $0.name == "web_search_exa" }?.description, ToolSourceCatalog.exa.tools[0].summary)

        let call = ToolCall(id: "1", name: "web_search_exa", argumentsJSON: #"{"query":"Swift language official site"}"#)
        let result = await host.execute(call)
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.hasPrefix("Title: Swift Programming Language"))
        XCTAssertLessThanOrEqual(result.text.count, ToolProfile.compact.maxResultCharacters + 40)

        // The first use named the service and was remembered; the second asked nothing.
        let note = try XCTUnwrap(approver.requests.first)
        XCTAssertEqual(approver.requests.count, 1)
        XCTAssertTrue(note.canRemember)
        XCTAssertEqual(note.serverName, "Exa")
        XCTAssertTrue(note.reason?.contains("Exa (exa.ai)") == true)
        _ = await host.execute(call)
        XCTAssertEqual(approver.requests.count, 1)

        let url = try XCTUnwrap(ToolSourceCatalog.exa.server?.url)
        let sent = MCPStubProtocol.requests(for: url)
        XCTAssertTrue(sent.allSatisfy { $0.header("Authorization") == nil }, "no token ever goes to a public server")
        let toolCall = try XCTUnwrap(sent.first { $0.rpcMethod == "tools/call" })
        XCTAssertEqual(toolCall.body?["params"]?["name"]?.string, "web_search_exa")
        XCTAssertEqual(toolCall.body?["params"]?["arguments"], .object([
            "query": .string("Swift language official site"), "numResults": .number(5),
            "objective": .string("Swift language official site"),
        ]))
    }

    func testRefusingTheFirstUseNoteSendsNothing() async throws {
        serveExa()
        let registry = makeRegistry()
        let host = try XCTUnwrap(registry.makeHost(approver: Refuses(), context: ToolContext(modelSource: .apple)))
        let result = await host.execute(ToolCall(id: "1", name: "web_search_exa", argumentsJSON: #"{"query":"swift"}"#))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, "The user did not allow this tool call.")
        let url = try XCTUnwrap(ToolSourceCatalog.exa.server?.url)
        XCTAssertFalse(MCPStubProtocol.requests(for: url).contains { $0.rpcMethod == "tools/call" })
    }

    func testAPageTheUserNeverWroteAsksWithTheServiceNamed() async throws {
        serveExa()
        let registry = makeRegistry()
        registry.integrations.permissions.agree(serverID: "exa")
        let approver = ScriptedConsent()
        let host = try XCTUnwrap(registry.makeHost(approver: approver, context: ToolContext(modelSource: .apple)))
        let call = ToolCall(id: "2", name: "web_fetch_exa", argumentsJSON: #"{"urls":["https://unwritten.example/a"]}"#)
        let result = await host.execute(call)
        XCTAssertTrue(result.isError)
        let question = try XCTUnwrap(approver.requests.first)
        XCTAssertEqual(question.serverName, "Exa")
        XCTAssertEqual(question.reason, "This address is not in your messages.")
        XCTAssertEqual(question.urls, ["https://unwritten.example/a"])
        XCTAssertFalse(question.canRemember)
    }

    func testALongPassageOfTheChatInASearchAsks() async throws {
        let registry = makeRegistry()
        registry.integrations.permissions.agree(serverID: "exa")
        let passage = String(repeating: "private words of the user ", count: 6)
        let approver = ScriptedConsent()
        let host = try XCTUnwrap(registry.makeHost(
            approver: approver, context: ToolContext(userTexts: [passage], modelSource: .apple)))
        let arguments = JSONValue.object(["query": .string(passage)]).jsonString()
        _ = await host.execute(ToolCall(id: "3", name: "web_search_exa", argumentsJSON: arguments))
        XCTAssertEqual(approver.requests.first?.reason, "This search repeats a long passage of the chat.")
    }

    func testAgreementCanBeTakenBack() {
        let store = ToolPermissionStore(defaults: testDefaults())
        XCTAssertFalse(store.hasAgreed(serverID: "exa"))
        store.agree(serverID: "exa")
        store.agree(serverID: "exa")
        store.agree(serverID: "deepwiki")
        XCTAssertTrue(store.hasAgreed(serverID: "exa"))
        store.forgetAgreement(serverID: "exa")
        XCTAssertFalse(store.hasAgreed(serverID: "exa"))
        XCTAssertTrue(store.hasAgreed(serverID: "deepwiki"))
    }
}

private final class FixtureAnchor {}

/// A recording of the public Exa server, one server-sent-event answer per file.
private func exaFixture(_ name: String) -> String {
    guard let url = Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "txt"),
        let text = try? String(contentsOf: url, encoding: .utf8)
    else { fatalError("Missing the \(name).txt fixture in the test bundle") }
    return text
}

/// The recorded answer with the JSON-RPC id of the request, so call order does not matter.
private func recordedReply(_ text: String, to request: RecordedRequest, headers: [String: String] = [:]) -> StubResponse {
    guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("data:") }),
        var message = JSONValue.parse(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))?.object
    else { fatalError("The fixture has no data line") }
    message["id"] = request.body?["id"]
    return .sse("event: message\ndata: \(JSONValue.object(message).jsonString())\n\n", headers: headers)
}
