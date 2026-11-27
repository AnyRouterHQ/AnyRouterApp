import Foundation
import SwiftData
import Testing
import UIKit
@testable import AnyRouter

struct CompactionLogicTests {
    /// The meter says how full the window is, with the needle at full once compaction would start (80%).
    @Test func theContextMeterFollowsTheShareOfTheWindow() {
        #expect(CompactionLogic.contextFraction(used: 420, window: 1_000) == 0.42)
        #expect(CompactionLogic.contextFraction(used: 420, window: nil) == nil)
        #expect(CompactionLogic.contextFraction(used: 420, window: 0) == nil)
        let cases: [(Double, String, String)] = [
            (0.05, "5% of context used", "gauge.with.dots.needle.0percent"),
            (0.3, "30% of context used", "gauge.with.dots.needle.33percent"),
            (0.5, "50% of context used", "gauge.with.dots.needle.50percent"),
            (0.7, "70% of context used", "gauge.with.dots.needle.67percent"),
            (0.85, "85% of context used", "gauge.with.dots.needle.100percent"),
        ]
        for (fraction, text, symbol) in cases {
            let meter = CompactionLogic.meter(fraction: fraction)
            #expect(meter.text == text && meter.symbol == symbol)
            #expect(UIImage(systemName: meter.symbol) != nil)
        }
    }

    private func message(_ role: ChatMessage.Role, _ text: String) -> ChatMessage { ChatMessage(role: role, content: text) }

    /// user, assistant, user, assistant, ... with short texts.
    private func chat(_ count: Int, text: String = "hello there") -> [ChatMessage] {
        (0..<count).map { message($0.isMultiple(of: 2) ? .user : .assistant, "\(text) \($0)") }
    }

    private func compaction(endingAt id: UUID, summary: String = "Earlier: actors.", dropped: Int = 4) -> Compaction {
        Compaction(lastMessageID: id, summary: summary, droppedCount: dropped, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func model(_ source: ModelSource, context: Int?) -> ModelDescriptor {
        ModelDescriptor(id: "m", source: source, displayName: "M", contextLength: context, capabilities: ["chat"],
                        sizeBytes: nil, isInstalled: true)
    }

    // MARK: Tokens and window

    @Test func fourBytesMakeAToken() {
    }

    @Test func aLocalModelIsHeldToWhatTheDeviceRunsNotToItsTrainedLength() {
        #expect(CompactionLogic.window(for: model(.gguf, context: 131_072)) == FitPlanner.maxContext)
        #expect(CompactionLogic.window(for: model(.mlx, context: 4_096)) == 4_096)
        #expect(CompactionLogic.window(for: model(.apple, context: 4_096)) == 4_096)
        #expect(CompactionLogic.window(for: model(.anyrouter, context: 200_000)) == 200_000)
    }

    @Test func aModelThatDoesNotSayHasNoWindow() {
        #expect(CompactionLogic.window(for: model(.anyrouter, context: nil)) == nil)
        #expect(CompactionLogic.window(for: model(.gguf, context: 0)) == nil)
    }

    @Test func everyBundledLocalModelGetsAWindowTheDeviceCanRun() throws {
        let entries = try BundledCatalog.load().models
        #expect(!entries.isEmpty)
        for entry in entries {
            let descriptor = entry.descriptor(isInstalled: false)
            let window = try #require(CompactionLogic.window(for: descriptor), "\(descriptor.displayName)")
            #expect(window <= FitPlanner.maxContext)
        }
    }

    // MARK: What is sent

    @Test func withoutACompactionEverythingIsSent() {
        let messages = chat(4)
        let context = CompactionLogic.context(messages: messages, compaction: nil)
        #expect(context.summary == nil)
        #expect(context.messages == messages)
    }

    @Test func aCompactionSendsItsSummaryAndOnlyTheMessagesAfterIt() {
        let messages = chat(6)
        let context = CompactionLogic.context(messages: messages, compaction: compaction(endingAt: messages[3].id))
        #expect(context.summary == "Earlier: actors.")
        #expect(context.messages == Array(messages[4...]))
    }

    @Test func aCompactionWhoseLastMessageIsGoneIsIgnored() {
        let messages = chat(4)
        let context = CompactionLogic.context(messages: messages, compaction: compaction(endingAt: UUID()))
        #expect(context.summary == nil)
        #expect(context.messages == messages)
    }

    // MARK: When

    @Test func compactionStartsAtEightyPercentOfTheWindow() {
        #expect(CompactionLogic.needsCompaction(used: 80, window: 100))
        #expect(!CompactionLogic.needsCompaction(used: 79, window: 100))
        #expect(!CompactionLogic.needsCompaction(used: 1_000_000, window: nil), "no known window, no automatic compaction")
    }

    // MARK: What

    @Test func aChatTooShortToFoldHasNoPlan() {
        #expect(CompactionLogic.plan(messages: chat(3), compaction: nil, window: 8_192, keepRecent: 2) == nil)
        #expect(CompactionLogic.plan(messages: chat(5), compaction: nil, window: 8_192, keepRecent: 4) == nil)
    }

    @Test func aModelWithoutAWindowIsPlannedAgainstTheDefaultOne() throws {
        let plan = try #require(CompactionLogic.plan(messages: chat(8), compaction: nil, window: nil, keepRecent: 4))
        #expect(plan.messages.count == 4)
    }

    @Test func theRecentMessagesAreKeptAsTheyAre() throws {
        let messages = chat(8)
        let plan = try #require(CompactionLogic.plan(messages: messages, compaction: nil, window: 8_192, keepRecent: 4))
        #expect(plan.messages == Array(messages[0..<4]))
        #expect(plan.lastMessageID == messages[3].id)
        #expect(plan.previousSummary == nil)
        #expect(plan.previousDropped == 0)
    }

    @Test func onlyTheOldestMessagesThatFitHalfTheWindowAreFolded() throws {
        // Each message costs 4 + 334 tokens; half of a 1,200-token window holds two of them, then stops.
        let messages = chat(8, text: String(repeating: "x", count: 1_000))
        let plan = try #require(CompactionLogic.plan(messages: messages, compaction: nil, window: 1_200, keepRecent: 2))
        #expect(plan.messages.count == 2)
        #expect(plan.lastMessageID == messages[1].id)
    }

    @Test func aMessageBiggerThanTheBudgetStillFoldsWithItsPartner() throws {
        let messages = chat(6, text: String(repeating: "x", count: 20_000))
        let plan = try #require(CompactionLogic.plan(messages: messages, compaction: nil, window: 400, keepRecent: 2))
        #expect(plan.messages.count == CompactionLogic.minimumToFold)
    }

    @Test func aSecondCompactionExtendsTheFirstSummaryAndTheCount() throws {
        let messages = chat(12)
        let earlier = compaction(endingAt: messages[3].id, summary: "S1", dropped: 4)
        let plan = try #require(CompactionLogic.plan(messages: messages, compaction: earlier, window: 8_192, keepRecent: 2))
        #expect(plan.messages == Array(messages[4..<10]))
        #expect(plan.previousSummary == "S1")
        #expect(plan.previousDropped == 4)
        let record = CompactionLogic.record(summary: "S2", plan: plan, now: Date(timeIntervalSince1970: 5))
        #expect(record.droppedCount == 10)
        #expect(record.lastMessageID == messages[9].id)
        #expect(record.summary == "S2")
    }

    @Test func aCompactionThatNoLongerAppliesStartsFromTheTop() throws {
        let messages = chat(8)
        let stale = compaction(endingAt: UUID())
        let plan = try #require(CompactionLogic.plan(messages: messages, compaction: stale, window: 8_192, keepRecent: 4))
        #expect(plan.messages == Array(messages[0..<4]))
        #expect(plan.previousSummary == nil)
    }

    // MARK: The request and its answer

    @Test func theRequestHoldsThePreviousSummaryAndTheMessagesWithTheirSpeakers() {
        let messages = [message(.user, "What is an actor?"), message(.assistant, "A type that guards state.")]
        let plan = CompactionPlan(messages: messages, lastMessageID: messages[1].id, previousSummary: "S1", previousDropped: 2)
        let request = CompactionLogic.request(for: plan)
        #expect(request.system == CompactionLogic.summarizerPrompt)
        #expect(request.messages.count == 1)
        let text = request.messages[0].content
        #expect(text.contains("Summary so far:\nS1"))
        #expect(text.contains("User: What is an actor?"))
        #expect(text.contains("Assistant: A type that guards state."))
        #expect(text.hasSuffix("Write the updated summary."))
    }

    @Test func aFirstRequestHasNoSummarySoFarAndALongMessageIsCut() {
        let long = message(.user, String(repeating: "y", count: CompactionLogic.maxMessageCharacters + 50))
        let plan = CompactionPlan(messages: [long, long], lastMessageID: long.id, previousSummary: nil, previousDropped: 0)
        let text = CompactionLogic.request(for: plan).messages[0].content
        #expect(!text.contains("Summary so far"))
        #expect(text.contains("…"))
        #expect(!text.contains(String(repeating: "y", count: CompactionLogic.maxMessageCharacters + 1)))
    }

    @Test func theAnswerIsTrimmedCappedAndNeverEmpty() {
        #expect(CompactionLogic.cleanSummary("  \n ") == nil)
        #expect(CompactionLogic.cleanSummary("\n  Short.  \n") == "Short.")
        let capped = CompactionLogic.cleanSummary(String(repeating: "z", count: CompactionLogic.maxSummaryCharacters + 10))
        #expect(capped?.count == CompactionLogic.maxSummaryCharacters)
    }

    @Test func theDividerSaysHowManyMessagesItStandsFor() {
        #expect(CompactionLogic.subtitle(droppedCount: 1) == "1 earlier message shortened")
        #expect(CompactionLogic.subtitle(droppedCount: 12) == "12 earlier messages shortened")
    }
}

struct CompactionRecordTests {
    @Test func aThreadKeepsItsCompactionsAsJSON() {
        let thread = ThreadRecord()
        #expect(thread.compactions.isEmpty)
        let one = Compaction(lastMessageID: UUID(), summary: "S", droppedCount: 4, createdAt: Date(timeIntervalSince1970: 100))
        thread.compactions = [one]
        #expect(thread.compactions == [one])
        thread.compactions = []
        #expect(thread.compactionData == nil)
    }

    @Test func unreadableDataReadsAsNoCompactions() {
        let thread = ThreadRecord()
        thread.compactionData = Data("nope".utf8)
        #expect(thread.compactions.isEmpty)
    }
}
