import Foundation
import Testing
@testable import AnyRouter

struct ChatSummaryLogicTests {
    private func model(_ id: String, _ source: ModelSource) -> ModelDescriptor {
        ModelDescriptor(id: id, source: source, displayName: id, contextLength: nil, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
    }

    private var apple: ModelDescriptor { model("apple/foundation", .apple) }
    private var local: ModelDescriptor { model("gguf/x/Qwen/q4.gguf", .gguf) }
    private var cloud: ModelDescriptor { model("anyrouter/auto", .anyrouter) }

    private func chat(_ count: Int) -> [ChatMessage] {
        (0..<count).map { ChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, content: "Message \($0) " + String(repeating: "x", count: 400)) }
    }

    private func action(
        _ messages: [ChatMessage], compaction: String? = nil, summarizedAt: Date? = nil, chat: ModelDescriptor? = nil,
        models: [ModelDescriptor]? = nil, online: Bool = true
    ) -> ChatSummaryLogic.Action {
        ChatSummaryLogic.action(
            messages: messages, compactionSummary: compaction, summarizedAt: summarizedAt, changedAt: Date(timeIntervalSince1970: 100),
            chat: chat ?? apple, models: models ?? [apple], isOnline: online)
    }

    @Test func aShortChatOrOneUnchangedSinceItsSummaryIsLeftAlone() {
        #expect(action(chat(5)) == .skip)
        #expect(action(chat(6), summarizedAt: Date(timeIntervalSince1970: 200)) == .skip)
        #expect(action(chat(6), summarizedAt: Date(timeIntervalSince1970: 50)) != .skip, "changed since its last summary")
    }

    @Test func aShortenedChatKeepsItsCompactionSummaryWithNoModelCall() {
        #expect(action(chat(6), compaction: "They planned a trip.") == .store("They planned a trip."))
        #expect(action(chat(6), compaction: String(repeating: "a", count: 700)) == .store(String(repeating: "a", count: 600)))
    }

    @Test func appleWritesTheSummaryFromTheNewestMessagesCutShort() throws {
        guard case .ask(let plan) = action(chat(20), chat: cloud, models: [apple, cloud]) else {
            Issue.record("Apple on the device writes it, even for a cloud chat")
            return
        }
        #expect(plan.model == apple && plan.system == ChatSummaryLogic.systemPrompt)
        let text = try #require(plan.messages.first?.content)
        #expect(text.hasPrefix("Conversation:\nUser: Message 8 ") && text.hasSuffix("\n\nSummary:"))
        #expect(!text.contains("Message 7 "), "only the newest twelve")
        #expect(!text.contains(String(repeating: "x", count: 300)), "each message is cut short")
    }

    @Test func aLocalModelIsNeverAskedAndACloudOneOnlyOnline() {
        #expect(action(chat(6), chat: local, models: [local]) == .skip)
        #expect(action(chat(6), chat: cloud, models: [cloud], online: false) == .skip)
        guard case .ask(let plan) = action(chat(6), chat: cloud, models: [cloud]) else {
            Issue.record("a cloud chat without Apple asks its own model")
            return
        }
        #expect(plan.model == cloud)
    }

    @Test func theAnswerLosesItsThinkingAndLabelAndIsCapped() {
        #expect(ChatSummaryLogic.clean("<think>hmm</think>Summary: They planned a trip.") == "They planned a trip.")
        #expect(ChatSummaryLogic.clean("  \n ") == nil)
        #expect(ChatSummaryLogic.clean(String(repeating: "b", count: 700))?.count == 600)
    }

    @Test func aChatWithAnyReplyFromThisDeviceStaysOffCloudModels() {
        #expect(ChatSummaryLogic.scope(replyModelIDs: ["anyrouter/auto"]) == .everywhere)
        #expect(ChatSummaryLogic.scope(replyModelIDs: ["anyrouter/auto", "apple/foundation"]) == .deviceOnly)
    }
}
