import Foundation
import Testing
@testable import AnyRouter

/// Tool calls for models that only write text: how each family is asked, how its calls are read back, and the loop that
/// runs them. The chat templates differ, so each format has its own cases.
struct LocalToolParserTests {
    private func run(_ format: LocalToolFormat?, _ chunks: [String]) -> (shown: String, end: LocalToolParser.Finished) {
        var parser = LocalToolParser(format: format)
        var shown = ""
        for chunk in chunks { shown += parser.feed(chunk) }
        return (shown, parser.finish())
    }

    private func chars(_ text: String) -> [String] { text.map(String.init) }

    private func args(_ call: ParsedToolCall) -> JSONValue? { JSONValue.parse(call.argumentsJSON) }

    // MARK: Qwen

    @Test func qwenCallsAreReadWhateverTheChunking() {
        let text = #"Let me check.<tool_call>{"name": "web_search_exa", "arguments": {"query": "swift 7"}}</tool_call>"#
        for chunks in [[text], chars(text), [String(text.prefix(20)), String(text.dropFirst(20))]] {
            let result = run(.qwen, chunks)
            #expect(result.shown == "Let me check.")
            #expect(result.end.text.isEmpty)
            #expect(result.end.calls.map(\.name) == ["web_search_exa"])
            #expect(args(result.end.calls[0])?["query"]?.string == "swift 7")
        }
    }

    @Test func aMarkerThatNeverCompletesIsShownAsText() {
        let result = run(.qwen, ["Use the <tool", " plain words."])
        #expect(result.shown + result.end.text == "Use the <tool plain words.")
        #expect(result.end.calls.isEmpty)
    }

    @Test func qwenReadsSeveralCallsAndStringArgumentsAndAMissingCloseTag() {
        let text = """
        <tool_call>
        {"name": "calculator", "arguments": "{\\"expression\\": \\"2+2\\"}"}
        </tool_call>
        <tool_call>
        {"name": "current_date_time", "parameters": {}}
        """
        let result = run(.qwen, [text])
        #expect(result.end.calls.map(\.name) == ["calculator", "current_date_time"])
        #expect(args(result.end.calls[0])?["expression"]?.string == "2+2")
        #expect(result.end.calls[1].argumentsJSON == "{}")
    }

    @Test func qwenCoderXMLCallsAreRead() {
        let text = "<tool_call>\n<function=web_search_exa>\n<parameter=query>\nswift news\n</parameter>\n<parameter=numResults>\n3\n</parameter>\n</function>\n</tool_call>"
        let call = run(.qwen, [text]).end.calls.first
        #expect(call?.name == "web_search_exa")
        #expect(call.flatMap(args)?["query"]?.string == "swift news")
        #expect(call.flatMap(args)?["numResults"]?.number == 3)
    }

    @Test func aCallThatCannotBeReadComesBackAsText() {
        let broken = "<tool_call>{not json}</tool_call>"
        let result = run(.qwen, [broken])
        #expect(result.end.calls.isEmpty)
        #expect(result.shown + result.end.text == broken, "nothing the model said is lost")
    }

    @Test func textAroundACallIsKept() {
        let result = run(.qwen, [#"A<tool_call>{"name":"x","arguments":{}}</tool_call>B"#])
        #expect(result.shown == "A")
        #expect(result.end.text == "B")
        #expect(result.end.calls.count == 1)
    }

    // MARK: Llama

    @Test func llamaPlainTextStreamsAtOnce() {
        var parser = LocalToolParser(format: .llama)
        #expect(parser.feed("The ") == "The ")
        #expect(parser.feed("answer") == "answer")
        #expect(parser.finish() == LocalToolParser.Finished(text: "", calls: []))
    }

    @Test func llamaReadsABareJSONCallWithParameters() {
        for chunks in [[#"{"name": "calculator", "parameters": {"expression": "6*7"}}"#], chars(#"  {"name": "calculator", "parameters": {"expression": "6*7"}}"#)] {
            let result = run(.llama, chunks)
            #expect(result.shown.isEmpty)
            #expect(result.end.calls.map(\.name) == ["calculator"])
            #expect(args(result.end.calls[0])?["expression"]?.string == "6*7")
        }
    }

    @Test func llamaReadsThePythonTagAndTheEndOfMessageToken() {
        let text = #"<|python_tag|>{"name": "current_date_time", "parameters": {}}<|eom_id|>"#
        for chunks in [[text], chars(text)] {
            let result = run(.llama, chunks)
            #expect(result.end.calls.map(\.name) == ["current_date_time"])
        }
    }

    @Test func llamaTextThatStartsWithABraceButIsNotACallIsNotLost() {
        let answer = #"{"colors": ["red", "blue"]}"#
        let result = run(.llama, [answer])
        #expect(result.end.calls.isEmpty)
        #expect(result.shown + result.end.text == answer)
    }

    @Test func llamaWaitsOnlyWhileTheStartIsUndecided() {
        var parser = LocalToolParser(format: .llama)
        #expect(parser.feed("  ") == "")
        #expect(parser.feed("<|pyth") == "")
        #expect(parser.feed("on rocks") == "  <|python rocks")
        #expect(parser.finish().calls.isEmpty)
    }

    // MARK: Gemma

    @Test func gemmaReadsKeywordCallsInAToolCodeBlock() {
        let text = "I will look it up.\n```tool_code\nweb_search_exa(query=\"swift \\\"7\\\"\", numResults=3, fresh=True, tags=['a', 'b'], skip=None)\n```"
        for chunks in [[text], chars(text)] {
            let result = run(.gemma, chunks)
            #expect(result.shown == "I will look it up.\n")
            let call = result.end.calls.first
            #expect(call?.name == "web_search_exa")
            let arguments = call.flatMap(args)
            #expect(arguments?["query"]?.string == "swift \"7\"")
            #expect(arguments?["numResults"]?.number == 3)
            #expect(arguments?["fresh"]?.bool == true)
            #expect(arguments?["tags"]?.array?.compactMap(\.string) == ["a", "b"])
            #expect(arguments?["skip"] == JSONValue.null)
        }
    }

    @Test func gemmaUnwrapsPrintAndModulePrefixes() {
        let text = "```tool_code\nprint(default_api.calculator(expression=\"1+(2*3)\"))\n```"
        let call = run(.gemma, [text]).end.calls.first
        #expect(call?.name == "calculator")
        #expect(call.flatMap(args)?["expression"]?.string == "1+(2*3)")
    }

    @Test func gemmaAcceptsAJSONCallAndNoArgumentsButNotPositionalOnes() {
        #expect(run(.gemma, ["```tool_code\n{\"name\": \"x\", \"arguments\": {\"a\": 1}}\n```"]).end.calls.map(\.name) == ["x"])
        #expect(run(.gemma, ["```tool_code\ncurrent_date_time()\n```"]).end.calls.first?.argumentsJSON == "{}")
        let positional = "```tool_code\ncalculator(\"1+1\")\n```"
        let result = run(.gemma, [positional])
        #expect(result.end.calls.isEmpty)
        #expect(result.shown + result.end.text == positional)
    }

    @Test func gemmaRejectsHalfWrittenCallsAndUnknownValues() {
        for line in ["calculator(expression=\"1+1\"", "calculator(expression=)", "calculator(expression=foo)", "calculator(a=[1, 2", "(a=1)", "calculator(a=\"x)"] {
            #expect(run(.gemma, ["```tool_code\n\(line)\n```"]).end.calls.isEmpty, "\(line)")
        }
    }

    @Test func gemmaReadsSeveralCallsOneToALine() {
        let text = "```tool_code\na()\n\nb(x=1)\n```"
        #expect(run(.gemma, [text]).end.calls.map(\.name) == ["a", "b"])
    }

    // MARK: No format

    @Test func withoutAFormatEverythingPassesThrough() {
        let text = "<tool_call>{}</tool_call>"
        let result = run(nil, [text])
        #expect(result.shown == text)
        #expect(result.end == LocalToolParser.Finished(text: "", calls: []))
    }
}

struct LocalToolFormatTests {
    private func local(_ id: String, name: String? = nil, source: ModelSource = .gguf) -> ModelDescriptor {
        ModelDescriptor(id: id, source: source, displayName: name ?? id, contextLength: nil, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
    }

    private let search = ToolSpec(
        name: "web_search_exa", title: nil, description: "Search the web.",
        inputSchemaJSON: #"{"type":"object","properties":{"query":{"type":"string"},"numResults":{"type":"integer"},"deep":{"type":"boolean"},"tags":{"type":"array"},"x":{"type":"number"},"o":{"type":"object"}},"required":["query"]}"#,
        isReadOnly: true)

    @Test func theFamilyDecidesTheFormat() {
        #expect(LocalToolFormat.detect(for: local("gguf/unsloth/Qwen3.5-4B-GGUF/q4.gguf")) == .qwen)
        #expect(LocalToolFormat.detect(for: local("mlx/mlx-community/gemma-4-e2b-it-4bit")) == .gemma)
        #expect(LocalToolFormat.detect(for: local("gguf/x/Llama-3.2-3B-Instruct-GGUF/q4.gguf")) == .llama)
        #expect(LocalToolFormat.detect(for: local("mlx/mlx-community/Meta-Llama3.1-8B")) == .llama)
        #expect(LocalToolFormat.detect(for: local("gguf/x/Llama-2-7B/q4.gguf")) == nil, "Llama 2 has no tool format")
        #expect(LocalToolFormat.detect(for: local("gguf/x/SmolLM3/q4.gguf")) == nil)
        #expect(LocalToolFormat.detect(for: local("anyrouter/qwen/qwen3", source: .anyrouter)) == nil, "only on-device models")
        #expect(LocalToolFormat.detect(for: local("apple/foundation", source: .apple)) == nil)
    }

    @Test func eachFormatNamesTheToolsAndTheWayToCallOne() {
        let qwen = LocalToolFormat.qwen.instructions(for: [search])
        #expect(qwen.contains("<tools>") && qwen.contains("<tool_call>") && qwen.contains("web_search_exa"))
        #expect(qwen.contains(#""type":"function""#))
        let llama = LocalToolFormat.llama.instructions(for: [search])
        #expect(llama.contains(#"{"name": "<tool name>", "parameters""#) && llama.contains("web_search_exa"))
        let gemma = LocalToolFormat.gemma.instructions(for: [search])
        #expect(gemma.contains("tool_code") && gemma.contains("tool_output"))
    }

    @Test func gemmaGetsPythonSignaturesWithRequiredArgumentsFirst() {
        let text = LocalToolFormat.gemma.instructions(for: [search])
        #expect(text.contains(#"def web_search_exa(query: str, deep: bool = None, numResults: int = None, o: dict = None, tags: list = None, x: float = None) -> str:"#))
        #expect(text.contains("\"\"\"Search the web.\"\"\""))
        let bare = ToolSpec(name: "t", title: nil, description: "d", inputSchemaJSON: "not json", isReadOnly: true)
        #expect(LocalToolFormat.gemma.instructions(for: [bare]).contains("def t() -> str:"))
        #expect(LocalToolFormat.qwen.instructions(for: [bare]).contains(#""parameters":{"type":"object"}"#))
    }

    @Test func resultsGoBackInTheFormOfTheFamily() {
        let results = [(name: "a", text: "one"), (name: "b", text: "two")]
        #expect(LocalToolFormat.qwen.resultMessage(results) == "<tool_response>\none\n</tool_response>\n<tool_response>\ntwo\n</tool_response>")
        #expect(LocalToolFormat.llama.resultMessage(results) == "The tool a returned:\none\n\nThe tool b returned:\ntwo")
        #expect(LocalToolFormat.gemma.resultMessage(results) == "```tool_output\none\n```\n```tool_output\ntwo\n```")
    }
}

/// A base engine that plays one reply per call and keeps what it was asked.
private final class Rounds: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String]
    private(set) var messages: [[ChatMessage]] = []
    private(set) var systemPrompts: [String?] = []

    init(_ replies: [String]) { self.replies = replies }

    func next(_ messages: [ChatMessage], _ params: GenerationParams) -> String {
        lock.withLock {
            self.messages.append(messages)
            systemPrompts.append(params.systemPrompt)
            return replies.isEmpty ? "done" : replies.removeFirst()
        }
    }
}

private struct RoundsEngine: ChatEngine {
    let source: ModelSource = .gguf
    let rounds: Rounds
    let models: [ModelDescriptor]
    /// Pieces per reply, to prove calls survive streaming.
    var pieces = 3

    func availableModels() async throws -> [ModelDescriptor] { models }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        let text = rounds.next(messages, params)
        let size = max(1, text.count / pieces)
        return AsyncThrowingStream { continuation in
            var rest = Substring(text)
            while !rest.isEmpty {
                continuation.yield(.text(String(rest.prefix(size))))
                rest = rest.dropFirst(size)
            }
            continuation.yield(.usage(prompt: 10, completion: 5))
            continuation.yield(.done(finishReason: "stop"))
            continuation.finish()
        }
    }
}

private struct AnswerHost: ToolHost {
    var specs: [ToolSpec] = [ToolSpec(name: "web_search_exa", title: nil, description: "Search.", inputSchemaJSON: #"{"type":"object"}"#, isReadOnly: true)]
    func execute(_ call: ToolCall) async -> ToolResult {
        ToolResult(callID: call.id, name: call.name, text: "found: \(call.argumentsJSON)", isError: call.name == "boom")
    }
}

/// Answers every call with a 6,000-character page, the most a device model's tool profile lets through.
private struct LongPageHost: ToolHost {
    var specs: [ToolSpec] = [ToolSpec(name: "web_search_exa", title: nil, description: "Search.", inputSchemaJSON: #"{"type":"object"}"#, isReadOnly: true)]
    func execute(_ call: ToolCall) async -> ToolResult {
        ToolResult(callID: call.id, name: call.name, text: String(repeating: "Long page text. ", count: 375), isError: false)
    }
}

struct LocalToolEngineTests {
    private let qwen = ModelDescriptor(
        id: "gguf/unsloth/Qwen3.5-4B-GGUF/q4.gguf", source: .gguf, displayName: "Qwen 3.5 4B", contextLength: nil,
        capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
    private let other = ModelDescriptor(
        id: "gguf/x/Phi-4/q4.gguf", source: .gguf, displayName: "Phi 4", contextLength: nil,
        capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
    private let call = #"<tool_call>{"name": "web_search_exa", "arguments": {"query": "swift"}}</tool_call>"#

    private func engine(_ replies: [String], enabled: Bool = true) -> (LocalToolEngine, Rounds) {
        let rounds = Rounds(replies)
        let base = RoundsEngine(rounds: rounds, models: [qwen, other])
        let ids = Counter()
        return (LocalToolEngine(wrapping: base, isEnabled: { enabled }, makeID: { "id\(ids.next())" }), rounds)
    }

    private func collect(_ stream: AsyncThrowingStream<ChatDelta, Error>) async throws -> [ChatDelta] {
        var all: [ChatDelta] = []
        for try await delta in stream { all.append(delta) }
        return all
    }

    private func text(_ deltas: [ChatDelta]) -> String {
        deltas.compactMap { if case .text(let piece) = $0 { piece } else { nil } }.joined()
    }

    @Test func onlyFamiliesWithAFormatGetTheToolsCapabilityAndOnlyWhenSwitchedOn() async throws {
        let on = try await engine([]).0.availableModels()
        #expect(on.map { $0.capabilities.contains("tools") } == [true, false])
        let off = try await engine([], enabled: false).0.availableModels()
        #expect(off.allSatisfy { !$0.capabilities.contains("tools") })
        #expect(engine([]).0.source == .gguf)
    }

    /// Agent design E4: four rounds of long results at 8,192 tokens. Every request fits the window less the answer's room.
    @Test func fourRoundsOfLongPagesEachFitTheWindow() async throws {
        let model = ModelDescriptor(
            id: qwen.id, source: .gguf, displayName: "Qwen", contextLength: 8192, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
        let rounds = Rounds([call, call, call, "Done."])
        let engine = LocalToolEngine(wrapping: RoundsEngine(rounds: rounds, models: [model]), isEnabled: { true })
        let question = [ChatMessage(role: .user, content: "news?")]
        _ = try await collect(engine.stream(model: model, messages: question, params: GenerationParams(systemPrompt: "Be brief."), tools: LongPageHost()))
        #expect(rounds.messages.count == 4)
        let window = try #require(CompactionLogic.window(for: model))
        for (sent, system) in zip(rounds.messages, rounds.systemPrompts) {
            let used = sent.reduce(TokenCountLogic.estimate(system ?? "")) { $0 + TokenCountLogic.estimate($1.content) + PromptAssembler.perMessageTokens }
            #expect(used <= window - RunBudgetLogic.reserve(window: window))
        }
        #expect(rounds.messages.last?.last?.content.contains("[Cut to fit the model's window.]") == true)
    }

    @Test func aCallIsRunThroughTheHostAndTheAnswerComesAfterIt() async throws {
        let (engine, rounds) = engine(["Looking. " + call, "It is Swift 7."])
        let deltas = try await collect(engine.stream(model: qwen, messages: [ChatMessage(role: .user, content: "news?")], params: GenerationParams(systemPrompt: "Be brief."), tools: AnswerHost()))
        #expect(text(deltas) == "Looking. It is Swift 7.")
        let calls = deltas.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
        let results = deltas.compactMap { if case .toolResult(let result) = $0 { result } else { nil } }
        #expect(calls.map(\.id) == ["id1"])
        #expect(calls.first?.name == "web_search_exa")
        #expect(results.first?.text == #"found: {"query":"swift"}"#)
        #expect(deltas.last == .done(finishReason: "stop"))
        #expect(deltas.contains(.usage(prompt: 20, completion: 10)), "usage adds up over the rounds")

        let prompts = rounds.systemPrompts
        #expect(prompts[0]?.hasPrefix("Be brief.") == true)
        #expect(prompts[0]?.contains("<tools>") == true)
        let second = rounds.messages[1]
        #expect(second.map(\.role) == [.user, .assistant, .user])
        #expect(second[1].content == "Looking. " + call, "the model sees its own call")
        #expect(second[2].content.hasPrefix("<tool_response>"))
        #expect(second[2].content.contains("found:"))
    }

    @Test func aReplyWithoutACallEndsAfterOneRound() async throws {
        let (engine, rounds) = engine(["Just words."])
        let deltas = try await collect(engine.stream(model: qwen, messages: [], params: GenerationParams(), tools: AnswerHost()))
        #expect(text(deltas) == "Just words.")
        #expect(rounds.messages.count == 1)
    }

    @Test func aModelThatKeepsCallingIsAskedToAnswerOnTheLastRound() async throws {
        let (engine, rounds) = engine(Array(repeating: call, count: 10))
        let deltas = try await collect(engine.stream(model: qwen, messages: [], params: GenerationParams(), tools: AnswerHost()))
        #expect(rounds.messages.count == LocalToolEngine.maxRounds)
        #expect(rounds.systemPrompts.last.flatMap { $0 } == nil, "no tool text on the last round")
        #expect(deltas.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }.count == LocalToolEngine.maxRounds - 1)
        #expect(text(deltas).contains("<tool_call>"), "a call on the last round is shown, not run")
    }

    @Test func aFailedToolIsReportedAndTheModelStillAnswers() async throws {
        let boom = #"<tool_call>{"name": "boom", "arguments": {}}</tool_call>"#
        let (engine, rounds) = engine([boom, "Sorry, that failed."])
        let deltas = try await collect(engine.stream(model: qwen, messages: [], params: GenerationParams(), tools: AnswerHost()))
        #expect(rounds.messages[1].last?.content.contains("Error: found:") == true)
        #expect(text(deltas) == "Sorry, that failed.")
    }

    @Test func withoutToolsASwitchOrAFormatTheBaseEngineIsUsedUntouched() async throws {
        let cases: [((LocalToolEngine, Rounds), ModelDescriptor, (any ToolHost)?)] = [
            (engine([call]), qwen, nil),
            (engine([call]), qwen, AnswerHost(specs: [])),
            (engine([call], enabled: false), qwen, AnswerHost()),
            (engine([call]), other, AnswerHost()),
        ]
        for (pair, model, host) in cases {
            let deltas = try await collect(pair.0.stream(model: model, messages: [], params: GenerationParams(systemPrompt: "x"), tools: host))
            #expect(text(deltas) == call)
            #expect(pair.1.systemPrompts == ["x"])
        }
        let (plain, rounds) = engine(["hi"])
        _ = try await collect(plain.stream(model: qwen, messages: [], params: GenerationParams()))
        #expect(rounds.messages.count == 1)
    }
}
