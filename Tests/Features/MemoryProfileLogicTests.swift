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
        let text = MemoryProfileLogic.render([preference], frozen: [preference.id], toCloud: false, deviceMemoriesInCloud: false, budget: 120)
        #expect(text == MemoryProfileLogic.heading + "\n- Answer in Vietnamese.")
    }

    @Test func anItemThatDoesNotFitIsLeftOutWholeAndASmallerOneStillGoesIn() {
        let long = item(String(repeating: "word ", count: 50), .note)
        let short = item("Short answers.", .preference)
        let budget = TokenCountLogic.estimate(MemoryProfileLogic.heading + "\n- Short answers.")
        let text = MemoryProfileLogic.render([long, short], frozen: [long.id, short.id], toCloud: false, deviceMemoriesInCloud: false, budget: budget)
        #expect(text == MemoryProfileLogic.heading + "\n- Short answers.")
    }

    @Test func anItemDeletedSinceTheChatStartedLeavesAndNothingLeftMeansNoProfile() {
        #expect(MemoryProfileLogic.render([], frozen: [UUID()], toCloud: false, deviceMemoriesInCloud: false, budget: 120) == nil)
    }

    @Test func itemsFromOnDeviceChatsReachCloudModelsOnlyWithTheSwitch() {
        #expect(MemoryProfileLogic.allows(.deviceOnly, toCloud: false, deviceMemoriesInCloud: false))
        #expect(MemoryProfileLogic.allows(.deviceOnly, toCloud: false, deviceMemoriesInCloud: false))
        #expect(!MemoryProfileLogic.allows(.deviceOnly, toCloud: true, deviceMemoriesInCloud: false))
        #expect(MemoryProfileLogic.allows(.deviceOnly, toCloud: true, deviceMemoriesInCloud: true))
        #expect(MemoryProfileLogic.allows(.everywhere, toCloud: true, deviceMemoriesInCloud: false))
        let private_ = item("I take insulin.", .profile, scope: .deviceOnly)
        #expect(MemoryProfileLogic.render([private_], frozen: [private_.id], toCloud: true, deviceMemoriesInCloud: false, budget: 500) == nil)
    }

    /// PLAN D34: Apple Intelligence on Private Cloud Compute is cloud for memory scope. A memory the user kept to "this
    /// device" never reaches Apple's servers unless the user allowed device memories in cloud chats.
    @Test func privateCloudComputeIsCloudForDeviceOnlyMemories() {
        let pcc = ApplePCCLogic.descriptor(.available(contextSize: 32_768))
        let onDevice = testModel(id: "apple/foundation", source: .apple)
        #expect(MemoryProfileLogic.isCloud(pcc))
        #expect(!MemoryProfileLogic.isCloud(onDevice))
        #expect(MemoryProfileLogic.isCloud(testModel(id: "anyrouter/x", source: .anyrouter)))
        #expect(!MemoryProfileLogic.isCloud(testModel(id: "gguf/x", source: .gguf)))
        #expect(!MemoryProfileLogic.allows(.deviceOnly, toCloud: MemoryProfileLogic.isCloud(pcc), deviceMemoriesInCloud: false))
        #expect(MemoryProfileLogic.allows(.deviceOnly, toCloud: MemoryProfileLogic.isCloud(onDevice), deviceMemoriesInCloud: false))
        #expect(MemoryProfileLogic.allows(.everywhere, toCloud: MemoryProfileLogic.isCloud(pcc), deviceMemoriesInCloud: false))
    }
}
