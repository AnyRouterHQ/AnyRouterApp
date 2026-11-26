import FoundationModels
import XCTest

@testable import AnyRouter

final class ToolSchemaTests: XCTestCase {
    private func parse(_ json: String) -> ToolSchemaNode { ToolSchemaNode.parse(json) }

    private func props(_ node: ToolSchemaNode) -> [ToolSchemaNode.Property] {
        guard case .object(let list) = node.kind else { XCTFail("not an object"); return [] }
        return list
    }

    func testPrimitivesRequiredFirstThenAlphabeticalWithDescriptions() {
        let node = parse(#"""
            {"type":"object","required":["query"],"properties":{
              "zeta":{"type":"boolean","description":"flag"},
              "limit":{"type":"integer"},
              "ratio":{"type":"number"},
              "query":{"type":"string","description":"what to find"}}}
            """#)
        let list = props(node)
        XCTAssertEqual(list.map(\.name), ["query", "limit", "ratio", "zeta"])
        XCTAssertEqual(list.map(\.isRequired), [true, false, false, false])
        XCTAssertEqual(list[0].node, ToolSchemaNode(kind: .string, description: "what to find"))
        XCTAssertEqual(list[1].node.kind, .integer)
        XCTAssertEqual(list[2].node.kind, .number)
        XCTAssertEqual(list[3].node, ToolSchemaNode(kind: .boolean, description: "flag"))
    }

    func testEnumArrayAndNestedObject() {
        let node = parse(#"""
            {"type":"object","properties":{
              "mode":{"enum":["a","b","a"]},
              "tags":{"type":"array","items":{"type":"string"}},
              "loose":{"type":"array"},
              "where":{"type":"object","required":["city"],"properties":{"city":{"type":"string"}}}}}
            """#)
        let list = Dictionary(uniqueKeysWithValues: props(node).map { ($0.name, $0.node) })
        XCTAssertEqual(list["mode"]?.kind, .choice(["a", "b"]))
        XCTAssertEqual(list["tags"]?.kind, .array(ToolSchemaNode(kind: .string, description: nil)))
        XCTAssertEqual(list["loose"]?.kind, .array(ToolSchemaNode(kind: .string, description: nil)))
        guard case .object(let inner)? = list["where"]?.kind else { return XCTFail("no nested object") }
        XCTAssertEqual(inner, [.init(name: "city", node: ToolSchemaNode(kind: .string, description: nil), isRequired: true)])
    }

    func testUnsupportedKeywordsDegradeToString() {
        let node = parse(#"""
            {"properties":{
              "a":{"anyOf":[{"type":"string"},{"type":"number"}]},
              "b":{"type":["integer","null"]},
              "c":{"enum":[1,2]},
              "d":{"enum":[]},
              "e":{"$ref":"#/defs/x"},
              "f":"not a schema",
              "":{"type":"string"}}}
            """#)
        let list = Dictionary(uniqueKeysWithValues: props(node).map { ($0.name, $0.node.kind) })
        XCTAssertEqual(list["a"], .string)
        XCTAssertEqual(list["b"], .integer)
        XCTAssertEqual(list["c"], .string)
        XCTAssertEqual(list["d"], .string)
        XCTAssertEqual(list["e"], .string)
        XCTAssertEqual(list["f"], .string)
        XCTAssertEqual(list.count, 6)
    }

    func testBadInputGivesEmptyObject() {
        for json in ["", "not json", "[]", #"{"type":"string","description":"x"}"#] {
            let node = parse(json)
            XCTAssertEqual(props(node), [], json)
        }
        XCTAssertEqual(parse(#"{"type":"string","description":"x"}"#).description, "x")
    }

    func testDeepNestingBecomesString() {
        var json = #"{"type":"string"}"#
        for _ in 0..<8 { json = "{\"type\":\"object\",\"properties\":{\"n\":" + json + "}}" }
        var node = parse(json)
        var depth = 0
        while case .object(let list) = node.kind, let next = list.first {
            node = next.node
            depth += 1
        }
        XCTAssertEqual(depth, ToolSchemaNode.maxDepth + 1)
        XCTAssertEqual(node.kind, .string)
    }

    func testFoundationModelsSchemaBuilds() throws {
        let node = parse(#"""
            {"type":"object","required":["q"],"properties":{
              "q":{"type":"string","description":"query"},
              "mode":{"enum":["fast","slow"]},
              "ids":{"type":"array","items":{"type":"integer"}},
              "where":{"type":"object","properties":{"lat":{"type":"number"},"on":{"type":"boolean"}}}}}
            """#)
        _ = try node.generationSchema(name: "search")
        _ = try parse("{}").generationSchema(name: "empty")
    }
}

final class AppleToolRunTests: XCTestCase {
    private struct FakeHost: ToolHost {
        var specs: [ToolSpec] = []
        var reply: @Sendable (ToolCall) async -> ToolResult
        func execute(_ call: ToolCall) async -> ToolResult { await reply(call) }
    }

    func testCallIsEmittedBeforeResultAndTextGoesBackToTheModel() async {
        let seen = LockedBox<[ChatDelta]>([])
        let host = FakeHost { call in
            ToolResult(callID: call.id, name: call.name, text: "sunny", isError: false)
        }
        let scope = ToolRunScope()
        let text = await scope.run(
            name: "weather", argumentsJSON: #"{"city":"Hue"}"#, host: host,
            emit: { delta in seen.value += [delta] }, makeID: { "id-1" })
        XCTAssertEqual(text, "sunny")
        XCTAssertEqual(seen.value, [
            .toolCall(ToolCall(id: "id-1", name: "weather", argumentsJSON: #"{"city":"Hue"}"#)),
            .toolResult(ToolResult(callID: "id-1", name: "weather", text: "sunny", isError: false)),
        ])
        XCTAssertEqual(scope.finishedCalls, 1)
    }

    func testErrorsAreMarkedAndTheResultIsNotCutAgain() {
        let failed = ToolResult(callID: "1", name: "t", text: "denied", isError: true)
        XCTAssertEqual(ToolRunScope.modelText(for: failed), "Error: denied")
        let long = ToolResult(callID: "1", name: "t", text: String(repeating: "x", count: 7000), isError: false)
        // The cap is ToolProfile's, applied by the host; the engine adds none of its own.
        XCTAssertEqual(ToolRunScope.modelText(for: long), long.text)
    }

    func testFreshIDsByDefault() async {
        let ids = LockedBox<[String]>([])
        let host = FakeHost { call in
            ids.value += [call.id]
            return ToolResult(callID: call.id, name: call.name, text: "", isError: false)
        }
        let scope = ToolRunScope()
        _ = await scope.run(name: "t", argumentsJSON: "{}", host: host, emit: { _ in })
        _ = await scope.run(name: "t", argumentsJSON: "{}", host: host, emit: { _ in })
        XCTAssertEqual(Set(ids.value).count, 2)
    }

    func testCancelAllStopsARunningCall() async {
        let started = LockedBox(false)
        let host = FakeHost { call in
            started.value = true
            do { try await Task.sleep(for: .seconds(60)) } catch {
                return ToolResult(callID: call.id, name: call.name, text: "cancelled", isError: true)
            }
            return ToolResult(callID: call.id, name: call.name, text: "late", isError: false)
        }
        let scope = ToolRunScope()
        let run = Task { await scope.run(name: "slow", argumentsJSON: "{}", host: host, emit: { _ in }) }
        for _ in 0..<2000 where !started.value { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(started.value)
        scope.cancelAll()
        let text = await run.value
        XCTAssertEqual(text, "Error: cancelled")
    }

    func testCallsAfterCancelAllSeeACancelledTask() async {
        let sawCancel = LockedBox(false)
        let host = FakeHost { call in
            sawCancel.value = Task.isCancelled
            return ToolResult(callID: call.id, name: call.name, text: "x", isError: Task.isCancelled)
        }
        let scope = ToolRunScope()
        scope.cancelAll()
        _ = await scope.run(name: "t", argumentsJSON: "{}", host: host, emit: { _ in })
        XCTAssertTrue(sawCancel.value)
    }

    func testCancellingTheCallerCancelsTheHostCall() async {
        let started = LockedBox(false)
        let host = FakeHost { call in
            started.value = true
            do { try await Task.sleep(for: .seconds(60)) } catch {
                return ToolResult(callID: call.id, name: call.name, text: "stopped", isError: true)
            }
            return ToolResult(callID: call.id, name: call.name, text: "late", isError: false)
        }
        let scope = ToolRunScope()
        let run = Task { await scope.run(name: "slow", argumentsJSON: "{}", host: host, emit: { _ in }) }
        for _ in 0..<2000 where !started.value { try? await Task.sleep(for: .milliseconds(5)) }
        run.cancel()
        let text = await run.value
        XCTAssertEqual(text, "Error: stopped")
    }

    func testTheEngineOffersEveryToolTheProfileLeftIn() async throws {
        let specs = (0..<12).map {
            ToolSpec(name: "t\($0)", title: nil, description: "tool \($0)",
                     inputSchemaJSON: #"{"type":"object","properties":{"q":{"type":"string"}}}"#, isReadOnly: true)
        }
        let host = FakeHost(specs: specs) { call in
            ToolResult(callID: call.id, name: call.name, text: "ok:" + call.argumentsJSON, isError: false)
        }
        let seen = LockedBox<[ChatDelta]>([])
        XCTAssertEqual(AppleDynamicTool.make(specs: specs, host: host, scope: ToolRunScope(), emit: { _ in }).count, 12)
        let shaped = ToolProfile.apple.shaped(specs)
        let tools = AppleDynamicTool.make(
            specs: shaped, host: host, scope: ToolRunScope(), emit: { seen.value += [$0] })
        XCTAssertEqual(tools.map(\.name), (0..<4).map { "t\($0)" })
        XCTAssertEqual(tools[0].description, "tool 0")
        let text = await tools[0].invoke(#"{"q":"a"}"#)
        XCTAssertEqual(text, #"ok:{"q":"a"}"#)
        XCTAssertEqual(seen.value.count, 2)
    }
}

final class AppleToolStreamTests: XCTestCase {
    /// Replays how the stream loop uses the tracker around a tool call.
    private func replay(_ steps: [String?]) -> String {
        var tracker = SnapshotDeltaTracker()
        var out = ""
        for step in steps {
            if let snapshot = step {
                if let delta = tracker.delta(for: snapshot) { out += delta }
            } else {
                tracker.markToolBoundary()
            }
        }
        return out
    }

    func testRestartedSnapshotAfterToolCallIsAppendedWholeAfterABlankLine() {
        let out = replay(["Let me check.", nil, "", "It is", "It is sunny."])
        XCTAssertEqual(out, "Let me check.\n\nIt is sunny.")
    }

    func testCumulativeSnapshotAfterToolCallAddsNoSeparatorAndNoDuplicate() {
        let out = replay(["Checking", nil, "Checking... done"])
        XCTAssertEqual(out, "Checking... done")
    }

    func testToolCallBeforeAnyTextChangesNothing() {
        XCTAssertEqual(replay([nil, "", "Answer"]), "Answer")
    }

    func testBoundaryWithShorterRestartStillKeepsEveryNewCharacter() {
        // Without the boundary the tracker would hold back the first characters of "Ok".
        XCTAssertEqual(replay(["A long first part.", nil, "Ok"]), "A long first part.\n\nOk")
    }

    func testCapabilitiesAdvertiseToolsOnlyWhenTheModelIsReady() {
        XCTAssertEqual(AppleFoundationEngine.capabilities(available: true), ["chat", "tools"])
        XCTAssertEqual(AppleFoundationEngine.capabilities(available: false), ["chat"])
    }
}
