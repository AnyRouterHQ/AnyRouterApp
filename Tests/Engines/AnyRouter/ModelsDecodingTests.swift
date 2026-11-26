import XCTest

@testable import AnyRouter

final class ModelsDecodingTests: XCTestCase {
    private let json = """
        {"object":"list","data":[
            {"id":"openai/gpt-5.4-mini","object":"model","provider":"OpenAI","category":"text",
              "context_length":128000,"capabilities":["chat","function-calling","vision"],
              "pricing":{"prompt":"10","completion":"30"}},
            {"id":"google/embed-1","category":"embedding","context_length":2048},
            {"id":"anyrouter/auto","name":"Auto","context_length":200000}
        ]}
        """

    func testDecodesChatModelsOnly() throws {
        let response = try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8))
        let models = response.descriptors(usable: true)
        XCTAssertEqual(models.map(\.id), ["anyrouter/openai/gpt-5.4-mini", "anyrouter/anyrouter/auto"])
        XCTAssertEqual(models[0].contextLength, 128000)
        XCTAssertEqual(models[0].capabilities, ["chat", "function-calling", "vision"])
        XCTAssertEqual(models[0].displayName, "openai/gpt-5.4-mini")
        XCTAssertEqual(models[1].displayName, "Auto")
        XCTAssertEqual(models[1].capabilities, ["chat"])
        XCTAssertTrue(models.allSatisfy { $0.source == .anyrouter })
    }

    func testDescriptionBecomesTheSummary() throws {
        let body = """
            {"data":[{"id":"anyrouter/coding","name":"AnyRouter Coding","description":"Routes coding work."},
                     {"id":"openai/gpt-5","name":"GPT-5"}]}
            """
        let models = try JSONDecoder().decode(ModelsResponse.self, from: Data(body.utf8)).descriptors(usable: true)
        XCTAssertEqual(models[0].summary, "Routes coding work.")
        XCTAssertNil(models[1].summary)
    }

    func testSignedOutModelsAreNotUsable() throws {
        let response = try JSONDecoder().decode(ModelsResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.descriptors(usable: false).allSatisfy { !$0.isInstalled })
    }

    func testChatRequestShape() throws {
        let engine = AnyRouterEngine(tokens: KeychainStore(service: "test.unused"))
        let model = ModelDescriptor(
            id: "anyrouter/openai/gpt-5.4-mini", source: .anyrouter, displayName: "m",
            contextLength: nil, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
        let message = ChatMessage(id: UUID(), role: .user, content: "hi", createdAt: Date())
        var params = GenerationParams()
        params.systemPrompt = "Be brief."
        let request = try engine.makeChatRequest(key: "sk-ar-v1-test", model: model, messages: [message], params: params)

        XCTAssertEqual(request.url?.absoluteString, "https://anyrouter.dev/api/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-ar-v1-test")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "HTTP-Referer"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-AnyRouter-Title"), "AnyRouter for iOS")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "openai/gpt-5.4-mini")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let wire = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(wire.map { $0["role"] }, ["system", "user"])
    }

    func testErrorMessageExtraction() {
        XCTAssertEqual(
            AnyRouterError.message(from: Data(#"{"error":{"message":"Invalid key"}}"#.utf8), status: 401), "Invalid key")
        XCTAssertEqual(
            AnyRouterError.message(from: Data(#"{"error":"invalid_grant","error_description":"Code expired"}"#.utf8), status: 400),
            "Code expired")
        XCTAssertEqual(AnyRouterError.message(from: Data(), status: 502), "Request failed (HTTP 502).")
    }
}
