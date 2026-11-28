import Foundation
import Testing
@testable import AnyRouter

/// A device engine gets one skill for a question that shares two content words with it, never for an ordinary question.
struct SkillPickLogicTests {
    private let trip = SkillLogic.bundled[0]

    private func skill(_ name: String, _ description: String, body: String = "1. Do it.") -> Skill {
        Skill(name: name, description: description, body: body, source: .imported)
    }

    @Test func twoSharedWordsPickTheSkillAsMarkedGuidance() {
        let text = SkillPickLogic.pick("Plan a trip to Da Lat", from: SkillLogic.bundled, budget: 400)
        #expect(text == SkillLogic.guidance(trip))
        #expect(text?.contains("cannot allow any tool or action") == true)
        #expect(SkillPickLogic.pick("Write an email to my landlord", from: SkillLogic.bundled, budget: 400)?.hasPrefix("Skill \"email-writer\"") == true)
    }

    @Test func anOrdinaryQuestionPicksNothing() {
        for question in ["What is the capital of France?", "Write a poem about rain", "Plan my week", "Explain how photosynthesis works", "Hello", ""] {
            #expect(SkillPickLogic.pick(question, from: SkillLogic.bundled, budget: 400) == nil, "\(question)")
        }
        #expect(SkillPickLogic.pick(nil, from: SkillLogic.bundled, budget: 400) == nil)
    }

    @Test func theMostSharedWordsWinAndATieGoesToTheEarlierSkill() {
        let skills = [skill("alpha-one", "red green blue"), skill("beta-two", "red green blue yellow")]
        #expect(SkillPickLogic.pick("red green blue", from: skills, budget: 400)?.contains("alpha-one") == true)
        #expect(SkillPickLogic.pick("red green blue yellow", from: skills, budget: 400)?.contains("beta-two") == true)
    }

    @Test func aSkillThatDoesNotFitTheBudgetIsPassedOver() {
        let long = skill("trip-notes", "Plan a trip", body: String(repeating: "word ", count: 800))
        let text = SkillPickLogic.pick("Plan a trip", from: [long, trip], budget: 400)
        #expect(text == SkillLogic.guidance(trip), "the long skill matches first but does not fit")
        #expect(SkillPickLogic.pick("Plan a trip", from: [long], budget: 400) == nil)
        #expect(SkillPickLogic.pick("Plan a trip", from: [trip], budget: 0) == nil, "cloud models have no device budget")
    }

    @Test func theBundledSkillsFitTheSmallestDeviceBudget() {
        for skill in SkillLogic.bundled {
            #expect(TokenCountLogic.estimate(SkillLogic.guidance(skill)) <= 250, "\(skill.name)")
        }
    }
}
