import Foundation
import Testing
@testable import AnyRouter

/// Replies as the small Qwen, Llama 3 and Gemma models write them through llama.cpp or MLX, cut where their tokenizers
/// cut, plus the ways they go wrong: a call cut off by the token limit, JSON with Python quotes, a call left half-open.
/// The rule under test: a call that reads is run, and anything that does not read reaches the person as text.
struct LocalToolSampleTests {
    private func run(_ format: LocalToolFormat, _ chunks: [String]) -> (shown: String, end: LocalToolParser.Finished) {
        var parser = LocalToolParser(format: format)
        var shown = ""
        for chunk in chunks { shown += parser.feed(chunk) }
        return (shown, parser.finish())
    }

    private func args(_ call: ParsedToolCall?) -> JSONValue? { call.flatMap { JSONValue.parse($0.argumentsJSON) } }

    // MARK: Qwen 2.5 / Qwen 3

    /// Qwen 3 thinks first, then writes the call on its own lines. The thinking is shown; the call is not.
    @Test func qwenThinkingThenACallInTokenPieces() {
        let chunks = [
            "<think>", "\n", "The user wants today's weather.", " I should search.", "\n", "</think>", "\n\n",
            "<", "tool", "_call", ">\n", "{\"", "name", "\": \"", "web", "_search", "_exa", "\", \"", "arguments", "\": {\"",
            "query", "\": \"", "Hanoi weather today", "\", \"", "numResults", "\": ", "3", "}}\n", "</", "tool", "_call", ">",
        ]
        let result = run(.qwen, chunks)
        #expect(result.shown == "<think>\nThe user wants today's weather. I should search.\n</think>\n\n")
        #expect(result.end.text.isEmpty)
        #expect(result.end.calls.map(\.name) == ["web_search_exa"])
        #expect(args(result.end.calls.first)?["query"]?.string == "Hanoi weather today")
        #expect(args(result.end.calls.first)?["numResults"]?.number == 3)
    }

    /// The token limit hits inside the arguments. No call runs, and the person sees what the model wrote.
    @Test func qwenCallCutOffByTheTokenLimitComesBackAsText() {
        let chunks = ["Searching.", "\n<tool", "_call>\n{\"name\": \"web_search_exa\", ", "\"arguments\": {\"query\": \"swi"]
        let result = run(.qwen, chunks)
        #expect(result.end.calls.isEmpty)
        #expect(result.shown + result.end.text == chunks.joined())
    }

    /// Small models sometimes write Python quotes. That is not JSON, so it is not guessed at.
    @Test func qwenPythonQuotedCallIsNotRun() {
        let text = "<tool_call>\n{'name': 'calculator', 'arguments': {'expression': '2+2'}}\n</tool_call>"
        let result = run(.qwen, [text])
        #expect(result.end.calls.isEmpty)
        #expect(result.shown + result.end.text == text)
    }

    /// One good call and one broken one: the good one runs, the broken one is shown.
    @Test func qwenGoodAndBrokenCallsInOneReply() {
        let good = "<tool_call>\n{\"name\": \"current_date_time\", \"arguments\": {}}\n</tool_call>"
        let broken = "<tool_call>\n{\"name\": \"calculator\", \"arguments\": {\"expression\": }\n</tool_call>"
        let result = run(.qwen, [good, "\n", broken])
        #expect(result.end.calls.map(\.name) == ["current_date_time"])
        #expect(result.end.text == broken)
    }

    // MARK: Llama 3.1 / 3.2

    /// Llama 3.2 answers a tool turn with bare JSON, often after a blank line, and ends with the end-of-message token.
    @Test func llamaBareJSONInTokenPiecesWithTheEndOfMessageToken() {
        let chunks = [
            "\n\n", "{\"", "type", "\":", " \"", "function", "\",", " \"", "name", "\":", " \"", "calculator", "\",",
            " \"", "parameters", "\":", " {\"", "expression", "\":", " \"", "17", " *", " 23", "\"}}", "<|eom_id|>",
        ]
        let result = run(.llama, chunks)
        #expect(result.shown.isEmpty)
        #expect(result.end.calls.map(\.name) == ["calculator"])
        #expect(args(result.end.calls.first)?["expression"]?.string == "17 * 23")
    }

    /// Llama 3.1 with the python tag, the arguments written as a JSON string.
    @Test func llamaPythonTagWithStringArguments() {
        let chunks = ["<|python", "_tag|>", #"{"name": "web_search_exa", "parameters": "{\"query\": \"swift 6.2\"}"}"#, "<|eot_id|>"]
        let result = run(.llama, chunks)
        #expect(result.end.calls.map(\.name) == ["web_search_exa"])
        #expect(args(result.end.calls.first)?["query"]?.string == "swift 6.2")
    }

    /// Cut off mid-call: the JSON never closes, so it comes back as text.
    @Test func llamaCallCutOffComesBackAsText() {
        let chunks = ["{\"name\": \"calculator\", ", "\"parameters\": {\"expression\": \"6*"]
        let result = run(.llama, chunks)
        #expect(result.end.calls.isEmpty)
        #expect(result.shown + result.end.text == chunks.joined())
    }

    /// A call without a name is not a call.
    @Test func llamaJSONWithoutANameIsText() {
        let text = #"{"parameters": {"expression": "1+1"}}"#
        let result = run(.llama, [text])
        #expect(result.end.calls.isEmpty)
        #expect(result.shown + result.end.text == text)
    }

    // MARK: Gemma 3

    /// Gemma 3 says a line, then wraps the call in print(default_api....) inside a tool_code block, fence split in tokens.
    @Test func gemmaToolCodeBlockInTokenPieces() {
        let chunks = [
            "Let me look", " that up.", "\n\n", "```", "tool", "_code", "\n", "print", "(", "default", "_api", ".", "web",
            "_search", "_exa", "(", "query", "=\"", "Hanoi weather", "\",", " numResults", "=", "3", "))", "\n", "```",
        ]
        let result = run(.gemma, chunks)
        #expect(result.shown == "Let me look that up.\n\n")
        #expect(result.end.text.isEmpty)
        #expect(result.end.calls.map(\.name) == ["web_search_exa"])
        #expect(args(result.end.calls.first)?["query"]?.string == "Hanoi weather")
        #expect(args(result.end.calls.first)?["numResults"]?.number == 3)
    }

    /// Cut off inside a string: nothing runs and the block is shown as written.
    @Test func gemmaCallCutOffInsideAStringComesBackAsText() {
        let chunks = ["```tool_code\n", "web_search_exa(query=\"Han"]
        let result = run(.gemma, chunks)
        #expect(result.end.calls.isEmpty)
        #expect(result.shown + result.end.text == chunks.joined())
    }

    /// A plain code fence is an answer, not a call: it streams as text.
    @Test func gemmaPlainCodeFenceIsAnAnswer() {
        let text = "Here it is:\n```python\nprint(2 + 2)\n```"
        let result = run(.gemma, Array(text).map(String.init))
        #expect(result.end.calls.isEmpty)
        #expect(result.shown + result.end.text == text)
    }
}
