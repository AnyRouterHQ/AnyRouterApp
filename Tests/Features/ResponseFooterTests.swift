import Foundation
import Testing
@testable import AnyRouter

/// The details sheet of a reply: sections and rows built from what is stored, and the "Copy all" text.
struct ResponseFooterTests {
    private func full() -> ResponseMetadata {
        var value = ResponseMetadata()
        value.requestID = "req_1"
        value.servedModelID = "anthropic/claude-haiku-4.5"
        value.servedModelName = "Claude Haiku 4.5"
        value.provider = "Anthropic"
        value.costUSD = Decimal(string: "0.0012")
        value.promptTokens = 120
        value.completionTokens = 84
        value.cachedTokens = 40
        value.upstreamLatencyMs = 300
        value.ttftMs = 400
        value.totalMs = 2400
        return value
    }

    private func make(
        name: String? = "Claude Haiku 4.5", id: String? = "anyrouter/anthropic/claude-haiku-4.5",
        metadata: ResponseMetadata? = nil, steps: [ToolStep] = [], reasoningMs: Int? = nil
    ) -> ReplyDetails {
        ReplyDetails.make(requestedName: name, requestedID: id, metadata: metadata, steps: steps, reasoningMs: reasoningMs)
    }

    private func value(_ label: String, in details: ReplyDetails) -> String? {
        details.sections.flatMap(\.rows).first { $0.label == label }?.value
    }

    private func step(_ name: String, text: String?, isError: Bool = false, children: [ToolStep]? = nil) -> ToolStep {
        let call = ToolCall(id: UUID().uuidString, name: name, argumentsJSON: "{}")
        let result = text.map { ToolResult(callID: call.id, name: name, text: $0, isError: isError) }
        return ToolStep(call: call, result: result, sourceID: nil, children: children)
    }

    @Test func aFullReplyHasEverySectionInOrder() {
        let details = make(metadata: full(), steps: [step("calculator", text: "2")], reasoningMs: 3000)
        #expect(details.sections.map(\.title) == ["Model", "Speed", "Tokens and cost", "Agent", "Context debug"])
        #expect(value("Name", in: details) == "Claude Haiku 4.5")
        #expect(value("ID", in: details) == "anthropic/claude-haiku-4.5")
        #expect(value("Engine", in: details) == "AnyRouter cloud")
        #expect(value("Provider", in: details) == "Anthropic")
        #expect(value("First token", in: details) == "0.4s")
        #expect(value("Speed", in: details) == "42 tok/s")
        #expect(value("Total time", in: details) == "2.4s")
        #expect(value("Upstream latency", in: details) == "0.3s")
        #expect(value("Thinking time", in: details) == "3.0s")
        #expect(value("Input", in: details) == "120")
        #expect(value("Output", in: details) == "84")
        #expect(value("Cached", in: details) == "40")
        #expect(value("Cost", in: details) == "$0.0012")
        #expect(value("Request ID", in: details) == "req_1")
    }

    @Test func aMissingValueIsHiddenNotShownAsADash() {
        var metadata = ResponseMetadata()
        metadata.totalMs = 900
        let details = make(name: nil, id: nil, metadata: metadata)
        #expect(details.sections.map(\.title) == ["Speed"])
        #expect(details.sections.flatMap(\.rows) == [ReplyDetails.Row(label: "Total time", value: "0.9s")])
        #expect(!details.copyAllText.contains("—"))
    }

    @Test func nothingStoredMeansNoSheet() {
        #expect(make(name: nil, id: nil).isEmpty)
        #expect(make(name: nil, id: nil, metadata: ResponseMetadata()).isEmpty)
    }

    @Test func aZeroCostStillReadsAsZeroDollars() {
        var metadata = ResponseMetadata()
        metadata.costUSD = 0
        #expect(value("Cost", in: make(metadata: metadata)) == "$0")
    }

    @Test func theNameFallsBackToAPrettyNameFromTheId() {
        #expect(value("Name", in: make(name: nil, id: "openai/gpt-6.2-sol")) == "Gpt 6.2 Sol")
    }

    @Test func aRouterShowsWhichModelItPicked() {
        var metadata = ResponseMetadata()
        metadata.servedModelName = "Nemotron 3.5 Bolt E4B"
        metadata.servedModelID = "nvidia/nemotron-3.5-bolt-e4b"
        let details = make(name: "AnyRouter", id: ModelDescriptor.autoRouterID, metadata: metadata)
        #expect(value("Name", in: details) == "AnyRouter → Nemotron 3.5 Bolt E4B")
        #expect(value("ID", in: details) == "nvidia/nemotron-3.5-bolt-e4b")
    }

    @Test(arguments: [
        ("apple/foundation", "Apple, on device"), ("gguf/org/repo/file.gguf", "llama.cpp, on device"),
        ("mlx/org/repo", "MLX, on device"), ("anyrouter/openai/gpt-5", "AnyRouter cloud"),
    ])
    func theEngineComesFromTheIdPrefix(id: String, engine: String) {
        #expect(value("Engine", in: make(id: id)) == engine)
    }

    @Test func anUnknownIdPrefixHidesTheEngine() {
        #expect(value("Engine", in: make(id: "other/model")) == nil)
        #expect(value("Engine", in: make(id: nil)) == nil)
    }

    @Test func eachToolCallShowsStatusAndResultSize() {
        let big = String(repeating: "x", count: 1536)
        let child = step("fetch_url", text: "page")
        let steps = [
            step("web_search", text: big),
            step("calculator", text: "boom", isError: true),
            step("shell", text: ToolResult.deniedText, isError: true),
            step("slow", text: nil),
            step("quiet", text: ""),
            step("subagent", text: "ok", children: [child]),
        ]
        let agent = make(steps: steps).sections.first { $0.title == "Agent" }
        #expect(agent?.rows == [
            ReplyDetails.Row(label: "Tool calls", value: "7"),
            ReplyDetails.Row(label: "web_search", value: "Done · 1.5 KB"),
            ReplyDetails.Row(label: "calculator", value: "Failed · 4 B"),
            ReplyDetails.Row(label: "shell", value: "Denied"),
            ReplyDetails.Row(label: "slow", value: "No result"),
            ReplyDetails.Row(label: "quiet", value: "Done"),
            ReplyDetails.Row(label: "subagent", value: "Done · 2 B"),
            ReplyDetails.Row(label: "fetch_url", value: "Done · 4 B"),
        ])
    }

    @Test func noToolCallsMeansNoAgentSection() {
        #expect(make(metadata: full()).sections.contains { $0.title == "Agent" } == false)
    }

    @Test func sizesReadInBytesKilobytesAndMegabytes() {
        #expect(ResponseFormat.size(0) == "0 B")
        #expect(ResponseFormat.size(1023) == "1023 B")
        #expect(ResponseFormat.size(1024) == "1.0 KB")
        #expect(ResponseFormat.size(5 * 1024 * 1024) == "5.0 MB")
    }

    @Test func copyAllIsPlainTextForABugReport() {
        var metadata = ResponseMetadata()
        metadata.requestID = "req_1"
        metadata.totalMs = 2400
        let text = make(name: "Haiku", id: nil, metadata: metadata).copyAllText
        #expect(text == "Model\nName: Haiku\n\nSpeed\nTotal time: 2.4s\n\nContext debug\nRequest ID: req_1")
    }
}
