import Foundation
import Testing
@testable import AnyRouter

struct ResumeLogicTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func decide(away: TimeInterval, _ delay: NewChatDelay, streaming: Bool = false) -> ResumeDecision {
        ResumeLogic.decide(backgroundedAt: t0, now: t0.addingTimeInterval(away), delay: delay, isStreaming: streaming)
    }

    @Test func oneMinuteIsTheDefault() {
        #expect(NewChatDelay.standard == .oneMinute)
        #expect(NewChatDelay.oneMinute.seconds == 60)
    }

    @Test func theBoundaryIsExactlyTheDelay() {
        #expect(decide(away: 59.9, .oneMinute) == .resume)
        #expect(decide(away: 60, .oneMinute) == .fresh)
        #expect(decide(away: 61, .oneMinute) == .fresh)
        #expect(decide(away: 299, .fiveMinutes) == .resume)
        #expect(decide(away: 300, .fiveMinutes) == .fresh)
        #expect(decide(away: 899, .fifteenMinutes) == .resume)
        #expect(decide(away: 900, .fifteenMinutes) == .fresh)
        #expect(decide(away: 3599, .oneHour) == .resume)
        #expect(decide(away: 3600, .oneHour) == .fresh)
    }

    @Test func immediatelyStartsANewChatOnEveryReturn() {
        #expect(decide(away: 0, .immediately) == .fresh)
        #expect(decide(away: 2, .immediately) == .fresh)
    }

    @Test func neverAlwaysKeepsTheConversation() {
        #expect(decide(away: 86_400 * 30, .never) == .resume)
        #expect(NewChatDelay.never.seconds == nil)
    }

    @Test func aReplyStillStreamingKeepsTheConversationWhateverTheDelay() {
        #expect(decide(away: 7200, .oneMinute, streaming: true) == .resume)
        #expect(decide(away: 7200, .immediately, streaming: true) == .resume)
    }

    @Test func noRecordedTimeOrAClockThatWentBackwardsKeepsTheConversation() {
        #expect(ResumeLogic.decide(backgroundedAt: nil, now: t0, delay: .immediately, isStreaming: false) == .resume)
        #expect(decide(away: -30, .immediately) == .resume)
    }

    @Test func everyChoiceHasATitleAndAUniqueId() {
        #expect(NewChatDelay.allCases.map(\.title) == ["Immediately", "1 minute", "5 minutes", "15 minutes", "1 hour", "Never"])
        #expect(Set(NewChatDelay.allCases.map(\.id)).count == NewChatDelay.allCases.count)
    }
}

@MainActor
struct ReturnToAppTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aLongBreakOpensAnEmptyChatAndClosesPanels() {
        let id = UUID()
        let shell = ShellModel(selectedThreadID: id)
        shell.isSidebarOpen = true
        #expect(shell.returned(backgroundedAt: t0, now: t0.addingTimeInterval(120), delay: .oneMinute))
        #expect(shell.selectedThreadID == nil, "no thread is created, the first send does that")
        #expect(!shell.isSidebarOpen)
    }

    @Test func aShortBreakKeepsTheConversation() {
        let id = UUID()
        let shell = ShellModel(selectedThreadID: id)
        #expect(!shell.returned(backgroundedAt: t0, now: t0.addingTimeInterval(10), delay: .oneMinute))
        #expect(shell.selectedThreadID == id)
    }

    @Test func aStreamingReplyStaysEvenAfterALongBreak() {
        let id = UUID()
        let shell = ShellModel(selectedThreadID: id)
        shell.isReplyStreaming = true
        #expect(!shell.returned(backgroundedAt: t0, now: t0.addingTimeInterval(9999), delay: .immediately))
        #expect(shell.selectedThreadID == id)
    }

    @Test func theChoiceAndTheTimeAwaySurviveARelaunch() {
        let defaults = testDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.newChatDelay == .oneMinute)
        #expect(first.lastBackgroundedAt == nil)
        first.newChatDelay = .oneHour
        first.lastBackgroundedAt = t0
        let second = AppSettings(defaults: defaults)
        #expect(second.newChatDelay == .oneHour)
        #expect(second.lastBackgroundedAt == t0)
        second.lastBackgroundedAt = nil
        #expect(AppSettings(defaults: defaults).lastBackgroundedAt == nil)
    }
}
