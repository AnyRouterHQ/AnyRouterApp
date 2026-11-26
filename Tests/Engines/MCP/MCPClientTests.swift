import XCTest

@testable import AnyRouter

final class MCPClientTests: XCTestCase {
    private func makeClient(
        url: URL,
        auth: MCPServer.Auth = .anyRouterSignIn,
        token: String? = "tok-secret"
    ) -> MCPClient {
        let server = MCPServer(id: "t", name: "Test", url: url, auth: auth)
        return MCPClient(server: server, token: { token }, session: MCPStubProtocol.session())
    }

    func testAnAnswerLargerThanTheCapIsRefused() async throws {
        let url = MCPStubProtocol.register { request in
            MCPFixtures.reply(MCPFixtures.toolsList, to: request).withPadding(8 * 1024)
        }
        let client = MCPClient(
            server: MCPServer(id: "t", name: "T", url: url, auth: .none),
            token: { nil }, session: MCPStubProtocol.session(), maxResponseBytes: 2 * 1024
        )
        do {
            _ = try await client.connect()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MCPError, .invalidResponse("The answer is larger than 2 KB."))
        }
    }

    func testAnAnswerUnderTheCapIsRead() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler())
        let client = MCPClient(
            server: MCPServer(id: "t", name: "T", url: url, auth: .none),
            token: { nil }, session: MCPStubProtocol.session(), maxResponseBytes: 64 * 1024
        )
        let tools = try await client.listTools()
        XCTAssertEqual(tools.count, 5)
    }

    func testHandshakeSendsInitializeThenInitializedAndKeepsSession() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler())
        let client = makeClient(url: url)

        let info = try await client.connect()
        XCTAssertEqual(info, MCPClient.ServerInfo(name: "anyrouter-mcp", version: "1.4.0", protocolVersion: "2025-06-18"))
        _ = try await client.listTools()

        let seen = MCPStubProtocol.requests(for: url)
        XCTAssertEqual(seen.compactMap(\.rpcMethod), ["initialize", "notifications/initialized", "tools/list"])
        let initialize = try XCTUnwrap(seen.first)
        XCTAssertEqual(initialize.body?["params"]?["protocolVersion"]?.string, MCPClient.requestedProtocolVersion)
        XCTAssertEqual(initialize.body?["params"]?["clientInfo"]?["name"]?.string, "AnyRouter for iOS")
        XCTAssertNil(initialize.header("Mcp-Session-Id"))
        // Later requests carry the session id and the negotiated version.
        XCTAssertEqual(seen[2].header("Mcp-Session-Id"), "sess-1")
        XCTAssertEqual(seen[2].header("MCP-Protocol-Version"), "2025-06-18")
        // The notification has no id: it is not a request.
        XCTAssertNil(seen[1].body?["id"])
    }

    func testBearerTokenIsSentOnlyWhenTheServerUsesAuth() async throws {
        let withAuth = MCPStubProtocol.register(standardMCPHandler())
        _ = try await makeClient(url: withAuth).connect()
        XCTAssertEqual(MCPStubProtocol.requests(for: withAuth).first?.header("Authorization"), "Bearer tok-secret")

        let open = MCPStubProtocol.register(standardMCPHandler())
        _ = try await makeClient(url: open, auth: .none).connect()
        XCTAssertNil(MCPStubProtocol.requests(for: open).first?.header("Authorization"))
    }

    func testServerWithoutSessionIdStillWorks() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler(sessionID: nil))
        let client = makeClient(url: url)
        let tools = try await client.listTools()
        XCTAssertEqual(tools.count, 5)
        XCTAssertNil(MCPStubProtocol.requests(for: url).last?.header("Mcp-Session-Id"))
    }

    func testToolListDecodesSchemaAnnotationsAndDefaults() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler())
        let tools = try await makeClient(url: url).listTools()

        XCTAssertEqual(tools.map(\.name), ["list_models", "recommend_model", "get_credits", "get_system_status", "create_key"])
        let list = tools[0]
        XCTAssertTrue(list.isReadOnly)
        XCTAssertEqual(list.displayName, "List models")
        XCTAssertEqual(list.inputSchema["properties"]?["free_only"]?["type"]?.string, "boolean")
        XCTAssertEqual(tools[1].inputSchema["required"]?.array, [.string("task")])
        // No annotations: not read-only, so approval is needed later. No description is fine.
        XCTAssertFalse(tools[3].isReadOnly)
        XCTAssertNil(tools[3].description)
        // A server that omits inputSchema still gets an object schema we can send to a model.
        let bare = try JSONDecoder().decode(MCPTool.self, from: Data(#"{"name":"ping"}"#.utf8))
        XCTAssertEqual(bare.inputSchema["type"]?.string, "object")
        XCTAssertFalse(tools[4].isReadOnly)
        XCTAssertEqual(tools[4].displayName, "Create key")
    }

    func testToolListFollowsPagination() async throws {
        let url = MCPStubProtocol.register { request in
            switch request.rpcMethod {
            case "tools/list":
                let first = request.body?["params"]?["cursor"] == nil
                let body = first
                    ? #"{"jsonrpc":"2.0","id":0,"result":{"tools":[{"name":"a"}],"nextCursor":"page2"}}"#
                    : #"{"jsonrpc":"2.0","id":0,"result":{"tools":[{"name":"b"}]}}"#
                return MCPFixtures.reply(body, to: request)
            default:
                return standardMCPHandler()(request)
            }
        }
        let tools = try await makeClient(url: url).listTools()
        XCTAssertEqual(tools.map(\.name), ["a", "b"])
    }

    func testToolListFromEventStream() async throws {
        let url = MCPStubProtocol.register { request in
            if request.rpcMethod == "tools/list" {
                // A priming event with empty data, a progress notification, then the answer.
                var response = MCPFixtures.reply(MCPFixtures.toolsList, to: request, sse: true)
                let answer = String(decoding: response.body, as: UTF8.self)
                response.body = Data(("id: 1\ndata:\n\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{}}\n\n" + answer).utf8)
                return response
            }
            return standardMCPHandler()(request)
        }
        let tools = try await makeClient(url: url).listTools()
        XCTAssertEqual(tools.count, 5)
    }

    func testCallToolSendsNameAndArgumentsAndReturnsText() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler())
        let client = makeClient(url: url)
        let result = try await client.callTool(
            name: "list_models",
            arguments: .object(["free_only": .bool(true), "limit": .number(3)])
        )

        XCTAssertFalse(result.isError)
        XCTAssertEqual(JSONValue.parse(result.text)?["total"]?.number, 1)
        let call = try XCTUnwrap(MCPStubProtocol.requests(for: url).last)
        XCTAssertEqual(call.rpcMethod, "tools/call")
        XCTAssertEqual(call.body?["params"]?["name"]?.string, "list_models")
        XCTAssertEqual(call.body?["params"]?["arguments"]?["free_only"]?.bool, true)
        XCTAssertEqual(call.body?["params"]?["arguments"]?["limit"]?.number, 3)
    }

    func testToolFailureIsInBandNotAThrow() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler { MCPFixtures.reply(MCPFixtures.callError, to: $0) })
        let result = try await makeClient(url: url).callTool(name: "revoke_key")
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, "Key key_123 not found in this workspace.")
    }

    func testMixedContentBlocks() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler { MCPFixtures.reply(MCPFixtures.callMixed, to: $0, sse: true) })
        let result = try await makeClient(url: url).callTool(name: "scrape")
        XCTAssertEqual(result.content, [
            .text("Found 2 pages."),
            .image(data: "aGVsbG8=", mimeType: "image/png"),
            .resource(uri: "file:///notes.md", mimeType: "text/markdown", text: "# Notes"),
            .resource(uri: "https://example.com/a", mimeType: nil, text: nil),
            .unsupported(type: "audio"),
        ])
        XCTAssertEqual(result.text, "Found 2 pages.\n[image: image/png]\n# Notes\n[resource: https://example.com/a]\n[audio content]")
    }

    func testStructuredContentIsTheFallbackText() throws {
        let json = try XCTUnwrap(JSONValue.parse(#"{"content":[],"structuredContent":{"credits":5}}"#))
        XCTAssertEqual(try MCPToolResult(json: json).text, #"{"credits":5}"#)
    }

    func testJSONRPCErrorBecomesAnRPCError() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler { request in
            MCPFixtures.reply(#"{"jsonrpc":"2.0","id":0,"error":{"code":-32602,"message":"Unknown tool: nope"}}"#, to: request)
        })
        do {
            _ = try await makeClient(url: url).callTool(name: "nope")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MCPError, .rpc(code: -32602, message: "Unknown tool: nope"))
        }
    }

    func testUnauthorizedIsReportedWithoutRetrying() async throws {
        let url = MCPStubProtocol.register { _ in
            StubResponse(status: 401, body: #"{"jsonrpc":"2.0","error":{"code":-32001,"message":"Unauthorized"},"id":null}"#)
        }
        do {
            _ = try await makeClient(url: url).connect()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MCPError, .unauthorized)
        }
        XCTAssertEqual(MCPStubProtocol.requests(for: url).count, 1)
    }

    func testHTTPErrorCarriesTheServerMessage() async throws {
        let url = MCPStubProtocol.register { _ in
            StubResponse(status: 429, body: #"{"error":{"message":"Rate limit exceeded"}}"#)
        }
        do {
            _ = try await makeClient(url: url).connect()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MCPError, .http(status: 429, message: "Rate limit exceeded"))
        }
    }

    func testNonMCPBodyIsAClearError() async throws {
        let url = MCPStubProtocol.register { _ in StubResponse(headers: ["Content-Type": "text/html"], body: "<html>hello</html>") }
        do {
            _ = try await makeClient(url: url).connect()
            XCTFail("expected an error")
        } catch {
            guard case MCPError.invalidResponse = error else { return XCTFail("got \(error)") }
        }
    }

    func testExpiredSessionReinitializesOnceAndRetries() async throws {
        let counter = Counter()
        let url = MCPStubProtocol.register { request in
            if request.rpcMethod == "tools/list", counter.next() == 1 {
                return StubResponse(status: 404, body: "")
            }
            return standardMCPHandler()(request)
        }
        let tools = try await makeClient(url: url).listTools()
        XCTAssertEqual(tools.count, 5)
        let methods = MCPStubProtocol.requests(for: url).compactMap(\.rpcMethod)
        XCTAssertEqual(methods.filter { $0 == "initialize" }.count, 2)
    }

    func testDroppedSessionIsAnErrorWhenItKeepsHappening() async throws {
        let url = MCPStubProtocol.register { request in
            request.rpcMethod == "tools/list" ? StubResponse(status: 404, body: "") : standardMCPHandler()(request)
        }
        do {
            _ = try await makeClient(url: url).listTools()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MCPError, .sessionExpired)
        }
    }

    func testConcurrentCallsInitializeOnce() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler())
        let client = makeClient(url: url)
        async let a = client.listTools()
        async let b = client.callTool(name: "get_credits")
        _ = try await (a, b)
        let methods = MCPStubProtocol.requests(for: url).compactMap(\.rpcMethod)
        XCTAssertEqual(methods.filter { $0 == "initialize" }.count, 1)
    }

    func testCloseEndsTheSession() async throws {
        let url = MCPStubProtocol.register(standardMCPHandler())
        let client = makeClient(url: url)
        try await client.connect()
        await client.close()
        let last = try XCTUnwrap(MCPStubProtocol.requests(for: url).last)
        XCTAssertEqual(last.method, "DELETE")
        XCTAssertEqual(last.header("Mcp-Session-Id"), "sess-1")
    }
}

final class JSONValueTests: XCTestCase {
    func testRoundTripKeepsIntegersAndNesting() throws {
        let text = #"{"a":1,"b":[true,null,"x",2.5],"c":{"d":"e"}}"#
        let value = try XCTUnwrap(JSONValue.parse(text))
        XCTAssertEqual(value["a"]?.number, 1)
        XCTAssertEqual(value.jsonString(), text)
    }

    func testBoolIsNotConfusedWithNumber() throws {
        let value = try XCTUnwrap(JSONValue.parse(#"{"on":true,"n":1}"#))
        XCTAssertEqual(value["on"], .bool(true))
        XCTAssertEqual(value["n"], .number(1))
    }
}
