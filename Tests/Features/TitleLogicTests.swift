import Foundation
import Testing
@testable import AnyRouter

struct TitleLogicTests {
    private let apple = testModel()
    private let cloud = testModel(id: "anyrouter/openai/gpt-5", source: .anyrouter)
    private let local = testModel(id: "gguf/x/y", source: .gguf)
    private let exchange = [
        ChatMessage(role: .user, content: "Plan a week in Lisbon"),
        ChatMessage(role: .assistant, content: "Day one: Alfama."),
    ]

    private func plan(
        source: TitleSource = .firstMessage, messages: [ChatMessage]? = nil, chat: ModelDescriptor? = nil,
        models: [ModelDescriptor] = [], isOnline: Bool = true
    ) -> TitlePlan? {
        TitleLogic.plan(source: source, messages: messages ?? exchange, chat: chat ?? cloud, models: models, isOnline: isOnline)
    }

    // MARK: When to ask

    @Test func aTitleTheUserSetOrAModelWroteIsNotAskedAgain() {
        #expect(plan(source: .user) == nil)
        #expect(plan(source: .generated) == nil)
        #expect(plan(source: .firstMessage) != nil)
    }

    @Test func nothingIsAskedBeforeThereIsAReply() {
        #expect(plan(messages: [exchange[0]]) == nil)
        #expect(plan(messages: [exchange[0], ChatMessage(role: .assistant, content: "  \n")]) == nil)
    }

    @Test func theRequestCarriesTheFirstExchangeAndTheRules() throws {
        let later = exchange + [ChatMessage(role: .user, content: "second"), ChatMessage(role: .assistant, content: "later reply")]
        let request = try #require(plan(messages: later))
        #expect(request.system == TitleLogic.systemPrompt)
        #expect(request.messages.count == 1)
        let text = request.messages[0].content
        #expect(text.contains("User: Plan a week in Lisbon"))
        #expect(text.contains("Assistant: Day one: Alfama."))
        #expect(!text.contains("second"))
        #expect(TitleLogic.systemPrompt.contains("2 to 6 words"))
        #expect(TitleLogic.maxTokens == 24)
    }

    @Test func aChatOfOnlyFilesIsTitledFromTheReply() throws {
        let files = [ChatMessage(role: .user, content: ""), exchange[1]]
        let request = try #require(plan(messages: files))
        let text = request.messages[0].content
        #expect(!text.contains("User:"))
        #expect(text.contains("Assistant: Day one"))
    }

    @Test func longTextsAreCutSoASmallWindowIsEnough() throws {
        let long = String(repeating: "a", count: 5_000)
        let request = try #require(plan(messages: [ChatMessage(role: .user, content: long), ChatMessage(role: .assistant, content: long)]))
        let text = request.messages[0].content
        #expect(text.count < 2 * TitleLogic.maxExcerpt + 100)
    }

    // MARK: Which engine

    @Test func appleWritesTheTitleWhenItIsReadyEvenForACloudChat() throws {
        let forCloud = try #require(plan(chat: cloud, models: [cloud, apple]))
        let forLocal = try #require(plan(chat: local, models: [local, apple]))
        #expect(forCloud.model == apple)
        #expect(forLocal.model == apple)
    }

    @Test func withoutAppleTheChatsOwnEngineWritesIt() throws {
        let forLocal = try #require(plan(chat: local, models: [local]))
        let forCloud = try #require(plan(chat: cloud, models: [cloud]))
        let notReady = testModel(installed: false)
        let skipsNotReady = try #require(plan(chat: local, models: [notReady, local]))
        #expect(forLocal.model == local)
        #expect(forCloud.model == cloud)
        #expect(skipsNotReady.model == local)
    }

    @Test func aTitleNeverLeavesTheDeviceForADeviceChat() throws {
        for chat in [apple, local] {
            for online in [true, false] {
                let request = try #require(plan(chat: chat, models: [cloud, chat], isOnline: online))
                #expect(request.model.source != .anyrouter)
            }
        }
    }

    @Test func aCloudChatOfflineKeepsItsFallbackTitle() {
        #expect(plan(chat: cloud, models: [cloud], isOnline: false) == nil)
    }

    // MARK: Cleaning

    @Test func cleanKeepsAPlainTitle() {
        #expect(TitleLogic.clean("Trip to Lisbon") == "Trip to Lisbon")
    }

    @Test func cleanRemovesQuotesLabelsAndTheClosingPeriod() {
        #expect(TitleLogic.clean("\"Trip to Lisbon.\"") == "Trip to Lisbon")
        #expect(TitleLogic.clean("“Trip to Lisbon”.") == "Trip to Lisbon")
        #expect(TitleLogic.clean("Title: Trip to Lisbon.") == "Trip to Lisbon")
        #expect(TitleLogic.clean("**Trip to Lisbon**") == "Trip to Lisbon")
        #expect(TitleLogic.clean("Viaje a Lisboa。") == "Viaje a Lisboa")
        #expect(TitleLogic.clean(".NET tips") == ".NET tips", "only the end loses its period")
    }

    @Test func cleanDropsThinkingAndKeepsTheFirstLine() {
        #expect(TitleLogic.clean("<think>The user asks about\ntravel.</think>\n\nTrip to Lisbon\nMore words") == "Trip to Lisbon")
    }

    @Test func cleanGivesNothingWhenNothingIsLeft() {
        #expect(TitleLogic.clean("") == nil)
        #expect(TitleLogic.clean("  \n ") == nil)
        #expect(TitleLogic.clean("<think>still thinking and out of tokens") == nil)
        #expect(TitleLogic.clean("\"\"") == nil)
    }

    @Test func cleanKeepsATitleWithinTheLengthLimit() throws {
        let long = String(repeating: "word ", count: 40)
        let cut = try #require(TitleLogic.clean(long))
        #expect(cut.count <= TitleLogic.maxLength)
        #expect(!cut.hasSuffix(" "))
    }
}
