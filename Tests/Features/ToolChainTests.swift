import Foundation
import Testing
@testable import AnyRouter

struct ToolChainTests {
    private func makeStep(_ id: String, _ name: String = "web_search", args: String = "{}",
                          result: ToolResult? = nil) -> ToolStep {
        ToolStep(call: ToolCall(id: id, name: name, argumentsJSON: args), result: result)
    }

    private func ok(_ id: String, _ name: String = "web_search") -> ToolResult {
        ToolResult(callID: id, name: name, text: "fine", isError: false)
    }

    private func failed(_ id: String, text: String = "boom") -> ToolResult {
        ToolResult(callID: id, name: "web_search", text: text, isError: true)
    }

    @Test func rowsKeepTheOrderOfTheCalls() {
        let chain = ToolChain(steps: [makeStep("b"), makeStep("a"), makeStep("c")], answerStarted: false)
        #expect(chain.rows.map(\.id) == ["b", "a", "c"])
    }

    @Test func aCallWithoutAResultIsRunningThenDoneOrFailedOrCancelled() {
        func status(_ result: ToolResult?) -> ToolRowLogic.Status {
            ToolChain(steps: [makeStep("1", result: result)], answerStarted: false).rows[0].status
        }
        #expect(status(nil) == .running)
        #expect(status(ok("1")) == .done)
        #expect(status(failed("1")) == .failed)
        #expect(status(failed("1", text: ToolRowLogic.cancelledText)) == .cancelled)
    }

    @Test func theChainStaysOpenUntilTheAnswerStarts() {
        let steps = [makeStep("1", result: ok("1")), makeStep("2", result: ok("2"))]
        #expect(!ToolChain(steps: steps, answerStarted: false).isCollapsed)
        #expect(ToolChain(steps: steps, answerStarted: true).isCollapsed)
    }

    @Test func aRunningCallKeepsTheChainOpenEvenAfterTheAnswerStarted() {
        let steps = [makeStep("1", result: ok("1")), makeStep("2")]
        #expect(!ToolChain(steps: steps, answerStarted: true).isCollapsed)
    }

    @Test func noCallsIsNeverACollapsedChain() {
        #expect(!ToolChain(steps: [], answerStarted: true).isCollapsed)
    }

    @Test func theHeadingCountsToolsAndFailures() {
        #expect(ToolChain(steps: [makeStep("1", result: ok("1"))], answerStarted: true).heading == "Used 1 tool")
        let three = [makeStep("1", result: ok("1")), makeStep("2", result: ok("2")), makeStep("3", result: ok("3"))]
        #expect(ToolChain(steps: three, answerStarted: true).heading == "Used 3 tools")
        let oneFailed = [makeStep("1", result: ok("1")), makeStep("2", result: failed("2"))]
        #expect(ToolChain(steps: oneFailed, answerStarted: true).heading == "Used 2 tools, 1 failed")
        #expect(ToolChain(steps: [makeStep("1"), makeStep("2")], answerStarted: false).heading == "Using 2 tools")
    }

    @Test func aRowNamesTheToolAndSummarisesItsArgument() {
        let search = makeStep("1", args: #"{"query":"swift 7"}"#)
        let row = ToolChain(steps: [search], answerStarted: false).rows[0]
        #expect(row.name == "Web search")
        #expect(row.summary == "swift 7")
        #expect(row.symbol == "magnifyingglass")
        #expect(row.title == "Searching the web for “swift 7”")
    }

    @Test func pagesShowHostAndPathAndOtherToolsTheirFirstTextArgument() {
        #expect(ToolRowLogic.summary(for: ToolCall(id: "1", name: "fetch_url", argumentsJSON: #"{"url":"https://example.com/a?b=1"}"#)) == "example.com/a")
        #expect(ToolRowLogic.summary(for: ToolCall(id: "1", name: "search_docs", argumentsJSON: #"{"topic":"actors","n":3}"#)) == "actors")
        #expect(ToolRowLogic.summary(for: ToolCall(id: "1", name: "current_date_time", argumentsJSON: "{}")) == nil)
        #expect(ToolRowLogic.summary(for: ToolCall(id: "1", name: "calculator", argumentsJSON: "not json")) == nil)
    }

    @Test func toolIdsAreSpelledOutAndUnknownToolsGetAWrench() {
        #expect(ToolRowLogic.displayName(for: "search_docs") == "Search docs")
        #expect(ToolRowLogic.displayName(for: "list-files") == "List files")
        #expect(ToolRowLogic.symbol(for: "search_docs") == "magnifyingglass")
        #expect(ToolRowLogic.symbol(for: "deploy") == "wrench.and.screwdriver")
        #expect(ToolRowLogic.symbol(for: "calculator") == "plusminus")
        #expect(ToolRowLogic.symbol(for: "fetch_url") == "globe")
        #expect(ToolRowLogic.symbol(for: "current_date_time") == "clock")
        #expect(ToolRowLogic.symbol(for: "read_attachment") == "paperclip")
    }

    @Test func longArgumentsAndResultsAreCutUntilShowMore() {
        #expect(!ToolRowLogic.exceedsPreview("short"))
        #expect(ToolRowLogic.exceedsPreview(String(repeating: "x", count: 401)))
        #expect(ToolRowLogic.exceedsPreview("1\n2\n3\n4\n5\n6\n7"))
        #expect(!ToolRowLogic.exceedsPreview("1\n2\n3\n4\n5\n6"))
    }
}
