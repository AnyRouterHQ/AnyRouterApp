import Foundation
import Testing
@testable import AnyRouter

struct MemoryEmbeddingLogicTests {
    @Test func tokenVectorsAverageIntoOneSentenceVector() {
        #expect(MemoryEmbeddingLogic.meanPool([[1, 2], [3, 4]]) == [2, 3])
        #expect(MemoryEmbeddingLogic.meanPool([]) == nil)
        #expect(MemoryEmbeddingLogic.meanPool([[]]) == nil)
        #expect(MemoryEmbeddingLogic.meanPool([[2, 2], [9]]) == [1, 1], "a vector of the wrong size adds nothing")
    }

    @Test func cosineIsOneForTheSameDirectionAndZeroWhenItCannotBeCompared() {
        #expect(abs(MemoryEmbeddingLogic.cosine([1, 2], [2, 4]) - 1) < 1e-9)
        #expect(abs(MemoryEmbeddingLogic.cosine([1, 0], [0, 1])) < 1e-9)
        #expect(MemoryEmbeddingLogic.cosine([1, 2], [1, 2, 3]) == 0)
        #expect(MemoryEmbeddingLogic.cosine([], []) == 0)
        #expect(MemoryEmbeddingLogic.cosine([0, 0], [1, 1]) == 0)
    }

    @Test func onlyAClearOutlierStandsOut() {
        let ids = (0..<5).map { _ in UUID() }
        let scores = MemoryEmbeddingLogic.standout(Dictionary(uniqueKeysWithValues: zip(ids, [0.9, 0.3, 0.31, 0.29, 0.3])))
        #expect((scores[ids[0]] ?? 0) >= MemoryEmbeddingLogic.standoutThreshold)
        #expect(ids.dropFirst().allSatisfy { (scores[$0] ?? 0) < MemoryEmbeddingLogic.standoutThreshold })
        #expect(MemoryEmbeddingLogic.standout([UUID(): 0.9, UUID(): 0.1]).isEmpty, "two items give no spread to stand out from")
        #expect(MemoryEmbeddingLogic.standout([UUID(): 0.5, UUID(): 0.5, UUID(): 0.5]).isEmpty)
    }

    @Test func aVectorSurvivesItsStoredForm() {
        let vector: [Float] = [0.25, -1.5, 3]
        #expect(MemoryEmbeddingLogic.vector(MemoryEmbeddingLogic.data(vector)) == vector)
    }

    @Test func meaningAddsAnItemNoWordFindsAndWordsStillCount() {
        let vegetarian = MemoryRecallLogic.Candidate(id: UUID(), text: "I am vegetarian")
        let dinner = MemoryRecallLogic.Candidate(id: UUID(), text: "I cook dinner at 7 pm")
        let car = MemoryRecallLogic.Candidate(id: UUID(), text: "My car is blue")
        let question = "Suggest a dinner recipe"
        #expect(MemoryRecallLogic.recall(question, from: [vegetarian, dinner, car], budget: 150).map(\.candidate.text) == ["I cook dinner at 7 pm"])
        let hybrid = MemoryRecallLogic.recall(question, from: [vegetarian, dinner, car], budget: 150, semantic: [vegetarian.id: 2.0, car.id: -1])
        #expect(Set(hybrid.map(\.candidate.text)) == ["I am vegetarian", "I cook dinner at 7 pm"])
        let meaningOnly = MemoryRecallLogic.recall("zzz", from: [vegetarian, car], budget: 150, semantic: [vegetarian.id: 1.6])
        #expect(meaningOnly.map(\.candidate.text) == ["I am vegetarian"])
    }
}
