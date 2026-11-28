import Foundation
import Testing
@testable import AnyRouter

/// What decides that Apple's model is asked, and what of its answer is kept (agent design 2.3, unit M6).
struct MemoryExtractionLogicTests {
    @Test func aSentenceAboutTheUserThatIsNotAQuestionIsAStatement() {
        for message in [
            "I'm training for a marathon", "My sister lives in Hue.", "Tôi ăn chay", "Mình sống ở Hà Nội",
            "What a day. I moved to Saigon in 2019", "Can I use a map? I live in Hue",
        ] {
            #expect(MemoryExtractionLogic.isFirstPersonStatement(message), "\(message)")
        }
    }

    @Test func questionsTasksAndLongTextsAreNot() {
        for message in [
            "Can I use a map?", "What is the capital of France?", "Do you remember that film?", "Write a poem about rain", "",
            "I " + String(repeating: "word ", count: 130),
        ] {
            #expect(!MemoryExtractionLogic.isFirstPersonStatement(message), "\(message.prefix(30))")
        }
    }

    @Test func theRequestCarriesTheMessage() {
        #expect(MemoryExtractionLogic.prompt(for: "I live in Hue") == "Message:\nI live in Hue")
        #expect(MemoryExtractionLogic.instructions.contains("Never invent anything"))
    }

    @Test func onlyPlainStatementsTheMessageSupportsAreKeptUpToThree() {
        let message = "I'm vegetarian and I live in Hue, my cat is called Mit"
        let kept = MemoryExtractionLogic.clean(
            ["I'm vegetarian", " I'm vegetarian ", "Is it hot?", "", "123", "My dog is Rex", "I love Hue", "I own a cat", "I live in Hue"],
            message: message)
        #expect(kept == ["I'm vegetarian", "I love Hue", "I own a cat"])
    }

    @Test func aStatementTooLongOrSharingOnlyShortWordsWithTheMessageIsDropped() {
        let long = String(repeating: "vegetarian ", count: 40)
        #expect(MemoryExtractionLogic.clean([long], message: "I'm vegetarian").isEmpty)
        #expect(MemoryExtractionLogic.clean(["I'm a doctor"], message: "I'm tired").isEmpty, "only \"m\" is shared")
        #expect(MemoryExtractionLogic.clean([], message: "I'm tired").isEmpty)
    }
}
