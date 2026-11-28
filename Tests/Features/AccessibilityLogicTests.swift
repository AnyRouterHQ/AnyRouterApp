import Testing
@testable import AnyRouter

struct AccessibilityLogicTests {
    @Test func announcesOnlyWhenAReplyWithTextStopsStreaming() {
        func say(_ was: Bool, _ now: Bool, content: Bool = true, failed: Bool = false) -> String? {
            AccessibilityLogic.replyFinishedAnnouncement(wasStreaming: was, isStreaming: now, hasContent: content, failed: failed)
        }
        #expect(say(true, false) == "Reply finished")
        #expect(say(false, true) == nil)
        #expect(say(false, false) == nil)
        #expect(say(true, true) == nil)
        #expect(say(true, false, content: false) == nil)
        #expect(say(true, false, failed: true) == nil)
    }

    @Test func modelPillValueNamesTheModelOrWhyThereIsNone() {
        #expect(AccessibilityLogic.modelPillValue(name: "Haiku 4.5", isLoading: true) == "Haiku 4.5")
        #expect(AccessibilityLogic.modelPillValue(name: nil, isLoading: true) == "Loading")
        #expect(AccessibilityLogic.modelPillValue(name: nil, isLoading: false) == "None chosen")
    }
}
