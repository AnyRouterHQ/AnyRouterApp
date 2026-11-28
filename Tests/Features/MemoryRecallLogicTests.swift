import Foundation
import Testing
@testable import AnyRouter

struct MemoryRecallLogicTests {
    private func candidates(_ texts: [String]) -> [MemoryRecallLogic.Candidate] {
        texts.map { MemoryRecallLogic.Candidate(id: UUID(), text: $0) }
    }

    private let unrelated = ["I work at a bakery", "My sister lives in Hue", "The car is blue", "Tea at four", "Piano on Sundays", "Gym on Monday"]

    @Test func theFactThatSharesAWordWithTheQuestionIsRecalled() {
        let facts = candidates(["My dog is called Mochi"] + unrelated)
        let hits = MemoryRecallLogic.recall("What treats can Mochi eat?", from: facts, budget: 150)
        #expect(hits.map(\.candidate.text) == ["My dog is called Mochi"])
    }

    @Test func anExactWordScoresAboveOneThatMatchesOnlyWithoutToneMarks() {
        let facts = candidates(["Toi thich pho ga", "Tôi thích phở bò"] + unrelated)
        let hits = MemoryRecallLogic.recall("Quán phở nào ngon?", from: facts, budget: 150)
        #expect(hits.map(\.candidate.text) == ["Tôi thích phở bò", "Toi thich pho ga"])
        #expect(hits[0].score > hits[1].score)
    }

    @Test func aSmallMemoryWhereEveryItemSharesTheWordStillRecallsThem() {
        let facts = candidates(["Mochi likes carrots", "Mochi sleeps late"])
        #expect(MemoryRecallLogic.recall("Mochi", from: facts, budget: 150).count == 2)
    }

    @Test func commonWordsAloneRecallNothing() {
        let facts = candidates(["What is this", "Tôi là ai"] + unrelated)
        #expect(MemoryRecallLogic.recall("What is this? Tôi là gì", from: facts, budget: 150).isEmpty)
        #expect(MemoryRecallLogic.recall("anything", from: [], budget: 150).isEmpty)
    }

    @Test func atMostThreeItemsAndOnlyWholeOnesThatFit() {
        let facts = candidates(["Mochi likes carrots", "Mochi sleeps late", "Mochi is three", "Mochi hates baths"] + unrelated)
        #expect(MemoryRecallLogic.recall("Mochi", from: facts, budget: 150).count == 3)
        #expect(MemoryRecallLogic.recall("Mochi", from: facts, budget: 5).isEmpty, "an item that does not fit is left out whole")
    }

    @Test func recalledItemsBecomeOneBlockUnderTheHeading() {
        let hit = MemoryRecallLogic.Hit(candidate: .init(id: UUID(), text: "My dog is called Mochi"), score: 1)
        #expect(MemoryRecallLogic.block([hit]) == MemoryRecallLogic.heading + "\n- My dog is called Mochi")
        #expect(MemoryRecallLogic.block([]) == nil)
    }

    @Test func aMemoryThatSharesOneWordWithALongQuestionAboutSomethingElseIsLeftOut() {
        let facts = candidates(["My dog is called Mochi"] + unrelated)
        #expect(MemoryRecallLogic.recall("Why is the dog in the Hachiko story so famous?", from: facts, budget: 150).isEmpty,
                "one word of four is not about the user's dog")
        #expect(MemoryRecallLogic.recall("Treats for my dog?", from: facts, budget: 150).map(\.candidate.text) == ["My dog is called Mochi"])
    }

    @Test func anEnglishPluralFindsItsSingular() {
        let facts = candidates(["I prefer trains over planes", "The glass is full"] + unrelated)
        #expect(MemoryRecallLogic.recall("Train or plane?", from: facts, budget: 150).map(\.candidate.text) == ["I prefer trains over planes"])
        #expect(MemoryRecallLogic.recall("glass", from: facts, budget: 150).map(\.candidate.text) == ["The glass is full"], "a double s stays")
    }

    @Test func wordsAreLowercasedLettersAndDigits() {
        #expect(MemoryRecallLogic.words("Room 204, floor-3!") == ["room", "204", "floor", "3"])
    }

    @Test func theFooterCountsTheMemories() {
        #expect(MemoryRecallLogic.usedLabel(1) == "Used 1 memory")
        #expect(MemoryRecallLogic.usedLabel(3) == "Used 3 memories")
    }
}
