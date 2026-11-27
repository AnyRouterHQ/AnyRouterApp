import Foundation
import Testing
@testable import AnyRouter

struct RememberLogicTests {
    private func saved(_ message: String) -> String? { RememberLogic.candidate(in: message)?.text }

    @Test func anAskToRememberSavesTheStatementWithoutTheAsk() {
        #expect(RememberLogic.candidate(in: "Remember that I'm vegetarian") == RememberLogic.Candidate(text: "I'm vegetarian", kind: .profile, explicit: true))
        #expect(RememberLogic.candidate(in: "Remember that my dog is called Mochi") == RememberLogic.Candidate(text: "My dog is called Mochi", kind: .fact, explicit: true))
        #expect(saved("Please remember that my sister lives in Hue. What should I bring her?") == "My sister lives in Hue.")
        #expect(saved("ok, remember that: I work night shifts!") == "I work night shifts!")
        #expect(saved("Thanks. Remember that I'm vegetarian.") == "I'm vegetarian.")
        #expect(saved("Remember that I'm vegetarian\nWhat can I cook?") == "I'm vegetarian")
    }

    @Test func vietnameseAsksAndPreferences() {
        #expect(RememberLogic.candidate(in: "Hãy nhớ rằng tôi ăn chay.") == RememberLogic.Candidate(text: "Tôi ăn chay.", kind: .profile, explicit: true))
        #expect(RememberLogic.candidate(in: "Nhớ rằng: 2 giờ chiều họp") == RememberLogic.Candidate(text: "2 giờ chiều họp", kind: .fact, explicit: true))
        #expect(saved("Bạn nhớ rằng mình dị ứng tôm nhé") == "Mình dị ứng tôm nhé")
        #expect(RememberLogic.candidate(in: "Từ giờ trả lời bằng tiếng Việt.") == RememberLogic.Candidate(text: "Trả lời bằng tiếng Việt.", kind: .preference, explicit: false))
        #expect(saved("Từ này nghĩa là gì") == nil, "a tone mark makes another word: this is not \"from now on\"")
    }

    @Test func preferencesAndFactsAboutTheUserAreAutomaticSaves() {
        #expect(RememberLogic.candidate(in: "From now on, answer in short sentences.") == RememberLogic.Candidate(text: "Answer in short sentences.", kind: .preference, explicit: false))
        #expect(RememberLogic.candidate(in: "Hi! My name is Lan.") == RememberLogic.Candidate(text: "My name is Lan.", kind: .profile, explicit: false))
        #expect(saved("Tên tôi là Lan") == "Tên tôi là Lan")
        #expect(saved("I\u{2019}m allergic to peanuts.") == "I\u{2019}m allergic to peanuts.")
    }

    @Test func questionsMemoriesOfThePastAndEmptyOrLongAsksSaveNothing() {
        #expect(saved("Remember that film we saw?") == nil)
        #expect(saved("I remember that day well.") == nil)
        #expect(saved("My name isn't important") == nil)
        #expect(saved("Remember that.") == nil)
        #expect(saved("Remember that " + String(repeating: "a", count: 300)) == nil)
        #expect(saved("What is the weather in Hue") == nil)
    }

    @Test func eachOutcomeHasItsWords() {
        #expect(RememberLogic.title(of: .saved) == "Memory updated")
        #expect(RememberLogic.title(of: .alreadySaved) == "Already in memory")
        #expect(RememberLogic.title(of: .refused("full")) == "Memory not saved")
        #expect(RememberLogic.title(of: .removed) == "Memory removed")
        #expect(RememberLogic.title(of: .undone) == "Memory update undone")
    }
}
