import Foundation
import Testing
@testable import AnyRouter

struct ToolDigestLogicTests {
    private func step(_ name: String, _ arguments: String) -> ToolStep {
        ToolStep(call: ToolCall(id: UUID().uuidString, name: name, argumentsJSON: arguments),
                 result: ToolResult(callID: "", name: name, text: "ok", isError: false))
    }

    private let search = #"{"query":"Da Lat weather"}"#
    private let page = #"{"url":"https://example.com/page"}"#

    @Test func aReplyThatUsedToolsSaysWhatItDidInOneLine() {
        #expect(ToolDigestLogic.digest([]) == nil)
        #expect(ToolDigestLogic.digest([step("web_search", search), step("fetch_url", page)])
                == "[Tools: Searched the web for “Da Lat weather”; Read example.com/page]")
        let many = Array(repeating: step("fetch_url", page), count: 5)
        #expect(ToolDigestLogic.digest(many) == "[Tools: Read example.com/page; Read example.com/page; Read example.com/page; and 2 more]")
    }

    @Test func onlyRepliesWithStepsGetTheDigest() {
        let question = ChatMessage(role: .user, content: "Weather?")
        let answer = ChatMessage(role: .assistant, content: "Sunny.")
        let turns = ToolDigestLogic.turns([question, answer], steps: [answer.id: [step("web_search", search)], question.id: []])
        #expect(turns[0] == question)
        #expect(turns[1].content == "Sunny.\n\n[Tools: Searched the web for “Da Lat weather”]")
        #expect(turns[1].id == answer.id)
    }
}
