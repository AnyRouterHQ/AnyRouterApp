import Foundation
import Testing
@testable import AnyRouter

struct ToolSummaryTests {
    private func steps(_ names: [String]) -> [ToolStep] {
        names.enumerated().map { index, name in
            ToolStep(call: ToolCall(id: "\(index)", name: name, argumentsJSON: "{}"),
                     result: ToolResult(callID: "\(index)", name: name, text: "ok", isError: false))
        }
    }

    private func text(_ names: [String]) -> String { ToolSummary.text(for: steps(names)) }

    @Test func noStepsIsNoSummary() {
        #expect(text([]).isEmpty)
    }

    @Test func oneKindReadsAsOnePhrase() {
        #expect(text(["web_search"]) == "Searched the web")
        #expect(text(["web_search_exa", "web_search"]) == "Searched the web")
        #expect(text(["fetch_url"]) == "Read 1 page")
        #expect(text(["fetch_url", "fetch_url", "fetch_url"]) == "Read 3 pages")
        #expect(text(["read_attachment"]) == "Read 1 file")
        #expect(text(["read_attachment", "read_attachment"]) == "Read 2 files")
        #expect(text(["calculator"]) == "Did the math")
        #expect(text(["current_date_time"]) == "Checked the time")
    }

    @Test func twoKindsAreJoinedInTheOrderTheyFirstAppear() {
        #expect(text(["web_search", "fetch_url", "fetch_url", "fetch_url"]) == "Searched the web and read 3 pages")
        #expect(text(["fetch_url", "web_search"]) == "Read 1 page and searched the web")
    }

    @Test func moreThanTwoKindsFoldTheRestIntoMoreSteps() {
        #expect(text(["web_search", "fetch_url", "fetch_url", "calculator", "calculator"])
            == "Searched the web, read 2 pages, and 2 more steps")
        #expect(text(["web_search", "fetch_url", "calculator"]) == "Searched the web, read 1 page, and 1 more step")
    }

    @Test func aToolTheAppDoesNotKnowIsNamedLikeTheRow() {
        #expect(text(["list_events"]) == "Used List events")
        #expect(text(["web_search", "list_events", "list_events"]) == "Searched the web and used List events")
    }

    @Test func theSameToolCalledTwiceIsOnePhrase() {
        #expect(text(["list_events", "list_events", "list_events"]) == "Used List events")
    }
}
