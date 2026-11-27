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
}
