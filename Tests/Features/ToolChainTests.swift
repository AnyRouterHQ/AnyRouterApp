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
        #expect(row.icon == .symbol("magnifyingglass"))
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

    /// Same icon as Settings > Integrations and the @ list: the source's logo for a tool it lists.
    @Test func aListedToolShowsItsSourcesLogoAndTitle() {
        let row = ToolChain(steps: [makeStep("1", "web_search_exa", args: #"{"query":"actors"}"#)], answerStarted: false).rows[0]
        #expect(row.icon == ToolSourceCatalog.exa.icon)
        #expect(row.icon == .asset("Logo-exa"))
        #expect(row.name == "Search the web")
        #expect(row.summary == "actors")
    }

    @Test func everyListedToolOfAPublicSourceMapsToItsSourceIcon() {
        for source in ToolSourceCatalog.publicSources {
            for tool in source.tools { #expect(ToolRowLogic.icon(for: tool.name) == source.icon, "\(tool.name)") }
        }
    }

    @Test func aToolWithoutALogoGetsASymbolFromItsNameAndBuiltInsKeepTheirOwn() {
        #expect(ToolRowLogic.icon(for: "crawl_site") == .symbol("point.3.connected.trianglepath.dotted"))
        #expect(ToolRowLogic.icon(for: "calculator") == .symbol("plusminus"))
        #expect(ToolRowLogic.icon(for: "deploy") == .symbol("wrench.and.screwdriver"))
    }

    private func sourcedStep(_ name: String, source: String?) -> ToolStep {
        ToolStep(call: ToolCall(id: "1", name: name, argumentsJSON: "{}"), result: nil, sourceID: source)
    }

    @Test func theSourceNotedAtCallTimeDecidesTheIcon() {
        func icon(_ name: String, _ source: String?) -> ToolSource.Icon {
            ToolChain(steps: [sourcedStep(name, source: source)], answerStarted: false).rows[0].icon
        }
        // AnyRouter tools show the AnyRouter mark, whatever they are called.
        #expect(icon("get_credits", ToolSourceCatalog.anyRouter.id) == ToolSourceCatalog.anyRouter.icon)
        // A custom server shows the server icon, whatever its tool is called.
        #expect(icon("web_search_exa", "my-server") == ToolSourceCatalog.customIcon)
        #expect(icon("calendar_lookup", "my-server") == .symbol("server.rack"))
        // A public service shows its logo.
        #expect(icon("anything", ToolSourceCatalog.exa.id) == ToolSourceCatalog.exa.icon)
        // The app's own tools keep their own symbols.
        #expect(icon("calculator", ToolSourceCatalog.device.id) == .symbol("plusminus"))
        // An older saved reply has no source: the name decides, as before.
        #expect(icon("web_search_exa", nil) == ToolSourceCatalog.exa.icon)
        #expect(icon("deploy", nil) == .symbol("wrench.and.screwdriver"))
    }

    @Test func aStepSavedWithoutASourceStillDecodes() throws {
        let old = #"{"call":{"id":"1","name":"calculator","argumentsJSON":"{}"}}"#
        let decoded = try JSONDecoder().decode(ToolStep.self, from: Data(old.utf8))
        #expect(decoded.sourceID == nil)
        let withSource = ToolStep(call: decoded.call, result: nil, sourceID: "exa")
        let again = try JSONDecoder().decode(ToolStep.self, from: JSONEncoder().encode(withSource))
        #expect(again.sourceID == "exa")
    }

    // MARK: Every branch of the sentence and the summary

    private func title(_ name: String, _ args: String, done: Bool) -> String {
        let call = ToolCall(id: "1", name: name, argumentsJSON: args)
        let result = done ? ToolResult(callID: "1", name: name, text: "x", isError: false) : nil
        return ToolRowLogic.title(for: ToolStep(call: call, result: result))
    }

    @Test func eachToolSaysWhatItDidWhileRunningAndWhenDone() {
        #expect(title("web_search", "{}", done: false) == "Searching the web")
        #expect(title("web_search", "{}", done: true) == "Searched the web")
        #expect(title("web_search", #"{"query":"a"}"#, done: true) == "Searched the web for “a”")
        #expect(title("fetch_url", #"{"url":"https://example.com/x"}"#, done: false) == "Reading example.com/x")
        #expect(title("fetch_url", "{}", done: true) == "Read a page")
        #expect(title("calculator", #"{"expression":"2+2"}"#, done: true) == "Calculated 2+2")
        #expect(title("calculator", "{}", done: false) == "Calculating a result")
        #expect(title("current_date_time", "{}", done: false) == "Checking the date and time")
        #expect(title("current_date_time", "{}", done: true) == "Checked the date and time")
        #expect(title("read_attachment", #"{"name":"a.txt"}"#, done: true) == "Read a.txt")
        #expect(title("read_attachment", "{}", done: false) == "Reading the attachments")
        #expect(title("search_docs", "{}", done: false) == "Searching the web")
        #expect(title("search_docs", "{}", done: true) == "Searched the web")
        #expect(title("deploy", "{}", done: false) == "Using deploy")
        #expect(title("deploy", "{}", done: true) == "Used deploy")
    }

    @Test func aFailedOrCancelledCallSaysSoAtTheEndOfTheSentence() {
        let call = ToolCall(id: "1", name: "calculator", argumentsJSON: #"{"expression":"1/0"}"#)
        let failed = ToolStep(call: call, result: ToolResult(callID: "1", name: "calculator", text: "bad", isError: true))
        let cancelled = ToolStep(call: call, result: ToolResult(callID: "1", name: "calculator", text: ToolRowLogic.cancelledText, isError: true))
        #expect(ToolRowLogic.title(for: failed) == "Calculated 1/0 failed")
        #expect(ToolRowLogic.title(for: cancelled) == "Calculated 1/0 cancelled")
    }

    @Test func theSummaryHasEveryBuiltInArgumentAndNilWhenNothingReadable() {
        func summary(_ name: String, _ args: String) -> String? {
            ToolRowLogic.summary(for: ToolCall(id: "1", name: name, argumentsJSON: args))
        }
        #expect(summary("web_search", #"{"query":"swift"}"#) == "swift")
        #expect(summary("web_search", "{}") == nil)
        #expect(summary("fetch_url", "{}") == nil)
        #expect(summary("calculator", #"{"expression":"2+2"}"#) == "2+2")
        #expect(summary("read_attachment", #"{"name":"a.txt"}"#) == "a.txt")
        #expect(summary("deploy", #"{"count":3}"#) == nil)
        #expect(summary("deploy", #"{"target":"  prod  "}"#) == "prod")
        #expect(summary("deploy", #"{"target":"   "}"#) == nil)
    }

    @Test func aLongArgumentIsCutWithAnEllipsis() {
        let long = String(repeating: "word ", count: 30)
        let summary = ToolRowLogic.summary(for: ToolCall(id: "1", name: "web_search", argumentsJSON: "{\"query\":\"\(long)\"}"))
        #expect(summary?.hasSuffix("…") == true)
        #expect((summary?.count ?? 0) <= ToolRowLogic.maxTitleArgument + 1)
    }
}
