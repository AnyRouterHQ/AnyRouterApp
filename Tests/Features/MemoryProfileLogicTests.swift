import Foundation
import Testing
@testable import AnyRouter

struct MemoryProfileLogicTests {
    private func item(_ text: String, _ kind: MemoryKind, scope: MemoryScope = .everywhere, at seconds: Double = 0) -> MemoryProfileLogic.Item {
        MemoryProfileLogic.Item(id: UUID(), kind: kind, text: text, scope: scope, createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func pinnedNotesComeFirstThenPreferencesThenAboutYouNewestFirstAndFactsWaitForRecall() {
        let older = item("I live in Hue.", .profile, at: 1)
        let newer = item("My name is Lan.", .profile, at: 2)
        let preference = item("Answer in Vietnamese.", .preference)
        let note = item("Call me by my first name.", .note)
        let fact = item("My dog is called Mochi.", .fact, at: 3)
        #expect(MemoryProfileLogic.frozenIDs([older, newer, preference, note, fact]) == [note.id, preference.id, newer.id, older.id])
    }

    @Test func theProfileIsOneLinePerItemUnderTheHeading() {
        let preference = item("Answer in Vietnamese.", .preference)
        let text = MemoryProfileLogic.render([preference], frozen: [preference.id], source: .apple, deviceMemoriesInCloud: false, budget: 120)
        #expect(text == MemoryProfileLogic.heading + "\n- Answer in Vietnamese.")
    }

    @Test func anItemThatDoesNotFitIsLeftOutWholeAndASmallerOneStillGoesIn() {
        let long = item(String(repeating: "word ", count: 50), .note)
        let short = item("Short answers.", .preference)
        let budget = TokenCountLogic.estimate(MemoryProfileLogic.heading + "\n- Short answers.")
        let text = MemoryProfileLogic.render([long, short], frozen: [long.id, short.id], source: .apple, deviceMemoriesInCloud: false, budget: budget)
        #expect(text == MemoryProfileLogic.heading + "\n- Short answers.")
    }

    @Test func anItemDeletedSinceTheChatStartedLeavesAndNothingLeftMeansNoProfile() {
        #expect(MemoryProfileLogic.render([], frozen: [UUID()], source: .apple, deviceMemoriesInCloud: false, budget: 120) == nil)
    }

    @Test func itemsFromOnDeviceChatsReachCloudModelsOnlyWithTheSwitch() {
        #expect(MemoryProfileLogic.allows(.deviceOnly, source: .apple, deviceMemoriesInCloud: false))
        #expect(MemoryProfileLogic.allows(.deviceOnly, source: .gguf, deviceMemoriesInCloud: false))
        #expect(!MemoryProfileLogic.allows(.deviceOnly, source: .anyrouter, deviceMemoriesInCloud: false))
        #expect(MemoryProfileLogic.allows(.deviceOnly, source: .anyrouter, deviceMemoriesInCloud: true))
        #expect(MemoryProfileLogic.allows(.everywhere, source: .anyrouter, deviceMemoriesInCloud: false))
        let private_ = item("I take insulin.", .profile, scope: .deviceOnly)
        #expect(MemoryProfileLogic.render([private_], frozen: [private_.id], source: .anyrouter, deviceMemoriesInCloud: false, budget: 500) == nil)
    }
}
