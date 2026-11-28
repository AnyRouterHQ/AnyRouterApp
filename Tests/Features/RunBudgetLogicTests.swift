import Foundation
import Testing
@testable import AnyRouter

struct RunBudgetLogicTests {
    private func result(_ name: String, _ arguments: String = "{}", text: String = "answer") -> RunBudgetLogic.Result {
        RunBudgetLogic.Result(name: name, argumentsJSON: arguments, text: text)
    }

    @Test func theAnswerKeepsMoreRoomOnALargerWindow() {
        #expect(RunBudgetLogic.reserve(window: 4096) == 700)
        #expect(RunBudgetLogic.reserve(window: 8192) == 1024)
    }

    @Test func aResultGetsAFixedCapOrAThirdOfWhatIsLeft() {
        #expect(RunBudgetLogic.resultCap(window: 4096, left: 3000) == 400)
        #expect(RunBudgetLogic.resultCap(window: 8192, left: 9000) == 800)
        #expect(RunBudgetLogic.resultCap(window: 8192, left: 300) == 100)
        #expect(RunBudgetLogic.resultCap(window: 4096, left: -50) == 0)
    }

    @Test func aLongResultIsCutToItsTokensAndSaysSo() {
        #expect(RunBudgetLogic.clip("Short.", tokens: 100) == "Short.")
        for page in [String(repeating: "Long page text. ", count: 375), String(repeating: "Trời đẹp quá. ", count: 300)] {
            let cut = RunBudgetLogic.clip(page, tokens: 400)
            #expect(TokenCountLogic.estimate(cut) <= 400)
            #expect(cut.hasSuffix("[Cut to fit the model's window.]"))
            #expect(page.hasPrefix(cut.components(separatedBy: "\n[Cut").first ?? ""))
        }
    }

    @Test func aClearedResultKeepsWhatWasCalledSoTheModelCanAskAgain() {
        let page = result("fetch_url", #"{"url":"https://example.com/page"}"#, text: String(repeating: "a", count: 4210))
        #expect(RunBudgetLogic.stub(page) == "[Result cleared: fetch_url https://example.com/page, 4210 characters]")
        #expect(RunBudgetLogic.stub(result("web_search", #"{"query":"da lat"}"#)) == "[Result cleared: web_search da lat, 6 characters]")
        #expect(RunBudgetLogic.stub(result("calculator")) == "[Result cleared: calculator, 6 characters]")
    }

    @Test func theOldestResultsAreClearedFirstAndTheNewestThreeNever() {
        let rounds = [[result("a"), result("b")], [result("c")], [result("d"), result("e")]]
        #expect(RunBudgetLogic.cleared(rounds) { _ in true } == rounds, "nothing is cleared while it fits")
        let never = RunBudgetLogic.cleared(rounds) { _ in false }
        #expect(never.flatMap { $0 }.map { $0.text.hasPrefix("[Result cleared") } == [true, true, false, false, false])
        var asked = 0
        let once = RunBudgetLogic.cleared(rounds) { _ in
            asked += 1
            return asked > 1
        }
        #expect(once.flatMap { $0 }.map { $0.text.hasPrefix("[Result cleared") } == [true, false, false, false, false])
    }

    @Test func theBudgetIsTheWindowLessTheAnswersRoom() {
        #expect(RunBudgetLogic.Budget(window: 8192, onDevice: true).limit == 7168)
        #expect(RunBudgetLogic.Budget(window: 128_000, onDevice: false).limit == 126_976)
    }

    @Test func stubbingTakesTheOldestAndNeverTheNewestThree() {
        let rounds = [[result("a"), result("b")], [result("c")], [result("d"), result("e")]]
        let cleared = { (count: Int) in RunBudgetLogic.stubbing(rounds, oldest: count).flatMap { $0 }.map { $0.text.hasPrefix("[Result cleared") } }
        #expect(cleared(0) == [false, false, false, false, false])
        #expect(cleared(1) == [true, false, false, false, false])
        #expect(cleared(9) == [true, true, false, false, false])
    }

    /// Agent design 3.4: a cloud run clears only when the rounds do not fit, and then at least 8,000 tokens at once,
    /// because each clearing breaks the provider's prompt cache from that point.
    @Test func aCloudRunClearsOnlyInLargeSteps() {
        let pages = (0..<5).map { result("r\($0)", text: String(repeating: "x", count: 5_000)) }
        let rounds = pages.map { [$0] }
        let characters = { (rounds: [[RunBudgetLogic.Result]]) in rounds.joined().reduce(0) { $0 + $1.text.count } }
        #expect(RunBudgetLogic.cloudStubs(rounds, sent: 0, limit: 100_000, tokens: characters) == 0, "it fits")
        #expect(RunBudgetLogic.cloudStubs(rounds, sent: 0, limit: 21_000, tokens: characters) == 2,
                "one stub would fit but frees under 8,000, so a second goes too")
        #expect(RunBudgetLogic.cloudStubs(rounds, sent: 0, limit: 1_000, tokens: characters) == 2, "all it may clear, though it still does not fit")
        #expect(RunBudgetLogic.cloudStubs(rounds, sent: 2, limit: 1_000, tokens: characters) == 2, "nothing more is left to clear")
        let short = (0..<5).map { [result("s\($0)", text: String(repeating: "x", count: 3_000))] }
        #expect(RunBudgetLogic.cloudStubs(short, sent: 0, limit: 10_000, tokens: characters) == 0, "clearing all it may frees under 8,000")
    }
}
