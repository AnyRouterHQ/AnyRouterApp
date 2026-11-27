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

    @Test func recalledItemsGoInFrontOfTheLastQuestionOnly() {
        let hit = MemoryRecallLogic.Hit(candidate: .init(id: UUID(), text: "My dog is called Mochi"), score: 1)
        let messages = [
            ChatMessage(role: .user, content: "Hi"), ChatMessage(role: .assistant, content: "Hello"),
            ChatMessage(role: .user, content: "Treats for Mochi?"),
        ]
        let applied = MemoryRecallLogic.applying([hit], to: messages)
        #expect(applied[0].content == "Hi")
        #expect(applied[2].content == MemoryRecallLogic.heading + "\n- My dog is called Mochi\n\nTreats for Mochi?")
        #expect(MemoryRecallLogic.applying([], to: messages) == messages)
        let noQuestion = [ChatMessage(role: .assistant, content: "Hello")]
        #expect(MemoryRecallLogic.applying([hit], to: noQuestion) == noQuestion)
    }

    @Test func wordsAreLowercasedLettersAndDigits() {
        #expect(MemoryRecallLogic.words("Room 204, floor-3!") == ["room", "204", "floor", "3"])
    }

    @Test func theBudgetFollowsTheEngineWindowAndTheFooterCounts() {
        func model(_ source: ModelSource, _ context: Int?) -> ModelDescriptor {
            ModelDescriptor(id: "m", source: source, displayName: "m", contextLength: context, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
        }
        #expect(MemoryRecallLogic.budget(for: model(.apple, nil)) == 150)
        #expect(MemoryRecallLogic.budget(for: model(.gguf, nil)) == 150)
        #expect(MemoryRecallLogic.budget(for: model(.mlx, 8192)) == 300)
        #expect(MemoryRecallLogic.budget(for: model(.anyrouter, 128_000)) == 1500)
        #expect(MemoryRecallLogic.usedLabel(1) == "Used 1 memory")
        #expect(MemoryRecallLogic.usedLabel(3) == "Used 3 memories")
    }
}
