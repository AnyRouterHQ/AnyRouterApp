import Foundation
import Testing
@testable import AnyRouter

struct DecisionsLogicTests {
    private func draft(_ kind: QuestionDraft.Kind = .yesNo, _ prompt: String = "Is it urgent?", list: String = "") -> QuestionDraft {
        QuestionDraft(kind: kind, prompt: prompt, list: list)
    }

    @Test func listsSplitOnCommasAndLinesAndDropBlanksAndDuplicates() {
        #expect(DecisionsLogic.items(" a, b ,,a\nc\n\n d ") == ["a", "b", "c", "d"])
        #expect(DecisionsLogic.items("").isEmpty)
    }

    @Test func aQuestionNeedsItsTextAndItsOptionsOrLevels() {
        #expect(DecisionsLogic.problem(with: draft()) == nil)
        #expect(DecisionsLogic.problem(with: draft(.yesNo, "  \n")) == "Write the question.")
        #expect(DecisionsLogic.problem(with: draft(.choice, list: "only")) == "Add at least two options.")
        #expect(DecisionsLogic.problem(with: draft(.choice, list: "a, b")) == nil)
        #expect(DecisionsLogic.problem(with: draft(.rubric, list: "low")) == "Add 2 to 10 levels.")
        #expect(DecisionsLogic.problem(with: draft(.rubric, list: "a,b,c")) == nil)
        #expect(DecisionsLogic.problem(with: draft(.rubric, list: (1...11).map(String.init).joined(separator: ","))) == "Add 2 to 10 levels.")
    }

    @Test func runIsEnabledOnlyWithAModelTextAndValidQuestions() {
        let good = [draft()]
        #expect(DecisionsLogic.canRun(model: "m", state: "text", questions: good))
        #expect(!DecisionsLogic.canRun(model: "", state: "text", questions: good))
        #expect(!DecisionsLogic.canRun(model: "m", state: " \n", questions: good))
        #expect(!DecisionsLogic.canRun(model: "m", state: "text", questions: []))
        #expect(!DecisionsLogic.canRun(model: "m", state: "text", questions: [draft(.yesNo, "")]))
        #expect(!DecisionsLogic.canRun(model: "m", state: String(repeating: "x", count: 12_001), questions: good))
        #expect(DecisionsLogic.canRun(model: "m", state: String(repeating: "x", count: 12_000), questions: good))
    }

    @Test func theRequestNumbersQuestionsInListOrderAndTrimsText() throws {
        let questions = [draft(.yesNo, " Urgent? "), draft(.choice, "Team?", list: "billing, tech"), draft(.rubric, "Tone?", list: "rude\nkind")]
        let request = try #require(DecisionsLogic.request(model: "m", state: "  hello \n", questions: questions))
        #expect(request.model == "m" && request.state == "hello")
        #expect(request.questions == [
            DecisionQuestion(id: "q1", prompt: "Urgent?", kind: .yesNo),
            DecisionQuestion(id: "q2", prompt: "Team?", kind: .choice(options: ["billing", "tech"])),
            DecisionQuestion(id: "q3", prompt: "Tone?", kind: .rubric(levels: ["rude", "kind"])),
        ])
        #expect(DecisionsLogic.request(model: "m", state: "", questions: questions) == nil)
    }

    @Test func theFreeDecisionModelIsPickedFirst() {
        let models = [DecisionModel(id: "x/a", name: "A"), DecisionModel(id: "anyrouter/decision", name: "D")]
        #expect(DecisionsLogic.initialModelID(in: models, current: "x/a") == "x/a")
        #expect(DecisionsLogic.initialModelID(in: models, current: "gone") == "anyrouter/decision")
        #expect(DecisionsLogic.initialModelID(in: [models[0]], current: "gone") == "x/a")
        #expect(DecisionsLogic.initialModelID(in: [], current: "gone") == "gone")
    }

    @Test func numbersReadAsPercentCostAndLatency() {
        #expect(DecisionsLogic.percent(0.92) == "92%")
        #expect(DecisionsLogic.percent(-1) == "0%")
        #expect(DecisionsLogic.percent(3) == "100%")
        #expect(DecisionsLogic.costText(nil) == "Not reported")
        #expect(DecisionsLogic.costText(0) == "Free")
        #expect(DecisionsLogic.costText(0.0012) == "$0.0012")
        #expect(DecisionsLogic.latencyText(0.84) == "840 ms")
        #expect(DecisionsLogic.latencyText(1.24) == "1.2 s")
    }

    @Test func recentRunsAreTitledByTheFirstLineOfTheText() {
        #expect(DecisionsLogic.title(forState: "  Refund please\nmore") == "Refund please")
        #expect(DecisionsLogic.title(forState: " \n ") == "Untitled run")
        #expect(DecisionsLogic.title(forState: "") == "Untitled run")
    }

    @Test func kindsHaveTitlesAndOnlyChoiceAndRubricAskForAList() {
        #expect(QuestionDraft.Kind.allCases.map(\.title) == ["Yes/no", "Choice", "Rubric"])
        #expect(QuestionDraft.Kind.yesNo.listPrompt == nil)
        #expect(QuestionDraft.Kind.choice.listPrompt != nil && QuestionDraft.Kind.rubric.listPrompt != nil)
        #expect(Set(QuestionDraft.Kind.allCases.map(\.id)).count == 3)
    }
}
