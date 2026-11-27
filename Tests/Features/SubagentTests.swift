import Foundation
import Testing
@testable import AnyRouter

struct SubagentTests {
    private func step(_ id: String, _ name: String, args: String = "{}", result: ToolResult? = nil, children: [ToolStep]? = nil) -> ToolStep {
        ToolStep(call: ToolCall(id: id, name: name, argumentsJSON: args), result: result, children: children)
    }

    private func done(_ id: String, _ name: String, _ text: String = "ok") -> ToolResult {
        ToolResult(callID: id, name: name, text: text, isError: false)
    }

    private let delegate = SubagentLogic.toolName

    // MARK: Reading the delegation

    @Test func onlyADelegationIsASubagent() {
        #expect(SubagentLogic.make(step("1", "web_search")) == nil)
        #expect(SubagentLogic.isSubagent(step("1", delegate)))
    }

    @Test func aFinishedSubagentCarriesItsTitleModelStepsAndAnswer() throws {
        let children = [step("a", "web_search", result: done("a", "web_search")), step("b", "fetch_url", result: done("b", "fetch_url"))]
        let call = step(
            "1", delegate, args: #"{"title":"  Research ","model":"anthropic/claude-haiku-4.5","task":"x"}"#,
            result: done("1", delegate, "Found it."), children: children)
        let subagent = try #require(SubagentLogic.make(call))
        #expect(subagent.title == "Research")
        #expect(subagent.modelLabel == "Haiku 4.5")
        #expect(subagent.steps == children)
        #expect(subagent.result == "Found it.")
        #expect(subagent.status == .done)
        #expect(subagent.id == "1")
    }

    @Test func aSubagentStillRunningHasNoAnswerYet() throws {
        let subagent = try #require(SubagentLogic.make(step("1", delegate, args: #"{"title":"Research"}"#)))
        #expect(subagent.status == .running)
        #expect(subagent.result == nil)
        #expect(subagent.steps.isEmpty)
        #expect(subagent.modelLabel == nil)
    }

    @Test func aFailedSubagentKeepsNoAnswerAsIfItWereOne() throws {
        let failed = ToolResult(callID: "1", name: delegate, text: "boom", isError: true)
        let subagent = try #require(SubagentLogic.make(step("1", delegate, result: failed)))
        #expect(subagent.status == .failed)
        #expect(subagent.result == nil)
    }

    @Test func missingOrBrokenArgumentsGiveATitleAndNoModel() throws {
        for args in ["not json", "{}", #"{"title":"   ","model":""}"#] {
            let subagent = try #require(SubagentLogic.make(step("1", delegate, args: args)))
            #expect(subagent.title == "Task", "\(args)")
            #expect(subagent.modelLabel == nil, "\(args)")
        }
    }

    // MARK: Heading

    @Test func theHeadingNamesTheSubagentAndCountsItsSteps() throws {
        func heading(_ count: Int) throws -> String {
            let children = (0..<count).map { step("c\($0)", "calculator") }
            let call = step("1", delegate, args: #"{"title":"Research"}"#, children: count == 0 ? nil : children)
            return SubagentLogic.heading(try #require(SubagentLogic.make(call)))
        }
        #expect(try heading(0) == "Subagent · Research")
        #expect(try heading(1) == "Subagent · Research · 1 step")
        #expect(try heading(4) == "Subagent · Research · 4 steps")
    }

    // MARK: In a reply

    @Test func subagentsAreCardsAfterTheToolsAndBeforeTheAnswer() {
        let search = step("s", "web_search", result: done("s", "web_search"))
        let sub = step("d", delegate, args: #"{"title":"Research"}"#, result: done("d", delegate))
        let parts = ReplyParts.make(reasoning: nil, steps: [sub, search], content: "Answer", isStreaming: false)
        #expect(parts.map(\.id) == ["tools", "subagent-d", "text"])
        #expect(parts.first == .toolStep([search]), "the tool line counts only the plain calls")
    }

    @Test func aReplyOfOnlyASubagentHasNoToolLine() {
        let sub = step("d", delegate, result: done("d", delegate))
        #expect(ReplyParts.make(reasoning: nil, steps: [sub], content: "", isStreaming: false).map(\.id) == ["subagent-d"])
    }

    @Test func pagesASubagentReadCountAsSourcesOfTheReply() throws {
        let page = step("p", "fetch_url", args: #"{"url":"https://docs.example.com/a"}"#, result: done("p", "fetch_url"))
        let sub = step("d", delegate, result: done("d", delegate), children: [page])
        let footer = try #require(ReplyFooter.make(
            content: "x", isStreaming: false, showsRegenerate: false, showsDetails: false,
            requestedName: nil, requestedID: nil, metadata: nil, steps: [sub]))
        #expect(footer.sources.map(\.host) == ["docs.example.com"])
    }

    // MARK: Stored data

    @Test func aStepSavedBeforeSubagentsExistedStillDecodes() throws {
        let old = #"{"call":{"id":"1","name":"web_search","argumentsJSON":"{}"},"sourceID":"exa"}"#
        let decoded = try JSONDecoder().decode(ToolStep.self, from: Data(old.utf8))
        #expect(decoded.children == nil)
        #expect(decoded.sourceID == "exa")
    }

    @Test func aStepWithChildrenSurvivesTheRoundTrip() throws {
        let original = step("1", delegate, children: [step("a", "calculator")])
        let again = try JSONDecoder().decode(ToolStep.self, from: JSONEncoder().encode(original))
        #expect(again == original)
    }
}
