import AppIntents
import Foundation
import Testing
@testable import AnyRouter

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(model: String, prompt: String)] = []
    var all: [(model: String, prompt: String)] { lock.withLock { recorded } }
    func record(model: String, prompt: String) { lock.withLock { recorded.append((model, prompt)) } }
}

private struct RecordingEngine: ChatEngine {
    let source: ModelSource
    var models: [ModelDescriptor]
    var reply = ["Answer."]
    var failure: String?
    let calls: Calls

    func availableModels() async throws -> [ModelDescriptor] { models }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        calls.record(model: model.id, prompt: messages.last?.content ?? "")
        let reply = reply, failure = failure
        return AsyncThrowingStream { continuation in
            for piece in reply { continuation.yield(.text(piece)) }
            if let failure {
                continuation.finish(throwing: TestFailure(message: failure))
            } else {
                continuation.yield(.done(finishReason: "stop"))
                continuation.finish()
            }
        }
    }
}

@MainActor
@Suite(.serialized)
struct HeadlessIntentTests {
    private let apple = RealisticModels.apple()
    private let local = testModel(id: "gguf/acme/small", source: .gguf)
    private let cloud = testModel(id: "anyrouter/auto", source: .anyrouter)

    private func engine(_ source: ModelSource, _ models: [ModelDescriptor], calls: Calls, reply: [String] = ["Answer."],
                        failure: String? = nil) -> RecordingEngine {
        RecordingEngine(source: source, models: models, reply: reply, failure: failure, calls: calls)
    }

    /// Replaces what the intents run on with scripted engines. `selected` is the default model of the app.
    private func install(_ engines: [RecordingEngine], selected: String, online: Bool = true) async throws {
        let registry = EngineRegistry()
        engines.forEach { registry.register($0) }
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        models.select(try #require(models.models.first { $0.id == selected }))
        let presets = PresetStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "presets-\(UUID().uuidString).json"),
            builtIns: try PresetStore.bundled(bundle: Bundle(for: PresetStore.self)))
        HeadlessChat.make = { HeadlessChat(registry: registry, models: models, presets: presets, isOnline: { online }) }
    }

    private func entity(_ id: String, _ models: [ModelDescriptor]) throws -> ModelEntity {
        ModelEntity(try #require(models.first { $0.id == id }))
    }

    // MARK: The four answering intents

    @Test func runPresetReturnsTheAnswerAndSendsThePresetWithTheText() async throws {
        let calls = Calls()
        try await install([engine(.apple, [apple], calls: calls, reply: ["Me and him go", " there."])], selected: apple.id)
        let result = try await RunPresetIntent(
            preset: PresetEntity(id: "fix-english", title: "Fix my English"), text: "  me and him goes there \n").perform()
        #expect(result.value == "Me and him go there.")
        let prompt = try #require(calls.all.first?.prompt)
        #expect(prompt.hasPrefix("Fix the grammar, spelling and wording"))
        #expect(prompt.hasSuffix("Text:\nme and him goes there"))
    }

    @Test func runPresetUsesTheDefaultsOfAPresetWithPickers() async throws {
        let calls = Calls()
        try await install([engine(.apple, [apple], calls: calls)], selected: apple.id)
        _ = try await RunPresetIntent(preset: PresetEntity(id: "reply-to-this", title: "Reply"), text: "Dinner at 5?").perform()
        let prompt = try #require(calls.all.first?.prompt)
        #expect(prompt.contains("Tone: polite and respectful."))
        #expect(prompt.hasSuffix("Message:\nDinner at 5?"))
    }

    @Test func summarizeReturnsTheSummary() async throws {
        let calls = Calls()
        try await install([engine(.apple, [apple], calls: calls, reply: ["Short."])], selected: apple.id)
        let result = try await SummarizeIntent(text: "A very long article.").perform()
        #expect(result.value == "Short.")
        #expect(calls.all.first?.prompt.hasPrefix("Summarize the text below") == true)
        #expect(calls.all.first?.prompt.hasSuffix("Text:\nA very long article.") == true)
    }

    @Test func translateAsksForTheChosenLanguage() async throws {
        let calls = Calls()
        try await install([engine(.apple, [apple], calls: calls, reply: ["Xin chao"])], selected: apple.id)
        let result = try await TranslateIntent(text: "Hello", language: .vietnamese).perform()
        #expect(result.value == "Xin chao")
        #expect(calls.all.first?.prompt.contains("into Vietnamese.") == true)
        #expect(calls.all.first?.prompt.hasSuffix("Text:\nHello") == true)
    }

    @Test func everyLanguageIsAChoiceOfTheTranslatePreset() throws {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        let translate = try #require(items.first { $0.id == InboundPreset.translate })
        let ids = Set(try #require(translate.options?.first).choices.map(\.id))
        #expect(Set(TranslationLanguage.allCases.map(\.rawValue)) == ids)
        #expect(Set(TranslationLanguage.caseDisplayRepresentations.keys) == Set(TranslationLanguage.allCases))
    }

    @Test func askWithModelUsesThatModelAndNoOther() async throws {
        let appleCalls = Calls(), localCalls = Calls()
        try await install([
            engine(.apple, [apple], calls: appleCalls),
            engine(.gguf, [local], calls: localCalls, reply: ["From the local one."]),
        ], selected: apple.id)
        let result = try await AskWithModelIntent(text: "What is 2+2?", model: try entity(local.id, [apple, local])).perform()
        #expect(result.value == "From the local one.")
        #expect(appleCalls.all.isEmpty)
        #expect(localCalls.all.map(\.model) == [local.id])
        #expect(localCalls.all.first?.prompt == "What is 2+2?")
    }

    @Test func aModelParameterOverridesTheDefaultOfARunPreset() async throws {
        let appleCalls = Calls(), localCalls = Calls()
        try await install([engine(.apple, [apple], calls: appleCalls), engine(.gguf, [local], calls: localCalls)], selected: apple.id)
        _ = try await SummarizeIntent(text: "Text", model: try entity(local.id, [apple, local])).perform()
        #expect(appleCalls.all.isEmpty && localCalls.all.count == 1)
    }

    // MARK: Offline

    @Test func offlineACloudDefaultGivesWayToAModelOnTheDevice() async throws {
        let cloudCalls = Calls(), appleCalls = Calls()
        try await install([engine(.anyrouter, [cloud], calls: cloudCalls), engine(.apple, [apple], calls: appleCalls)],
                          selected: cloud.id, online: false)
        _ = try await SummarizeIntent(text: "Text").perform()
        #expect(cloudCalls.all.isEmpty)
        #expect(appleCalls.all.count == 1)
    }

    @Test func offlineAnAskedForCloudModelIsRefusedWithAModelToSwitchTo() async throws {
        let calls = Calls()
        try await install([engine(.anyrouter, [cloud], calls: calls), engine(.apple, [apple], calls: calls)],
                          selected: apple.id, online: false)
        await #expect(throws: HeadlessError.self) {
            _ = try await AskWithModelIntent(text: "Hi", model: try entity(cloud.id, [cloud])).perform()
        }
        #expect(calls.all.isEmpty)
        do {
            _ = try await AskWithModelIntent(text: "Hi", model: try entity(cloud.id, [cloud])).perform()
        } catch let error as HeadlessError {
            #expect(error.message.contains("You are offline") && error.message.contains("Switch to Apple Intelligence"))
        }
    }

    // MARK: Failures

    @Test func aFailingEngineAndAnEmptyAnswerAreErrorsNotBlankResults() async throws {
        let calls = Calls()
        try await install([engine(.apple, [apple], calls: calls, failure: "model is busy")], selected: apple.id)
        do {
            _ = try await SummarizeIntent(text: "Text").perform()
            Issue.record("expected a failure")
        } catch let error as HeadlessError {
            #expect(error == .failed(model: "Apple Intelligence", reason: "model is busy"))
        }

        try await install([engine(.apple, [apple], calls: calls, reply: ["  "])], selected: apple.id)
        do {
            _ = try await SummarizeIntent(text: "Text").perform()
            Issue.record("expected a failure")
        } catch let error as HeadlessError {
            #expect(error == .empty(model: "Apple Intelligence"))
        }
    }

    @Test func noTextAnUnknownPresetAndAMissingModelAreSaidPlainly() async throws {
        let calls = Calls()
        try await install([engine(.apple, [apple], calls: calls)], selected: apple.id)
        await #expect(throws: HeadlessError.noText) { _ = try await SummarizeIntent(text: " \n").perform() }
        await #expect(throws: HeadlessError.noText) { _ = try await AskWithModelIntent(text: "", model: ModelEntity(apple)).perform() }
        await #expect(throws: HeadlessError.unknownPreset) {
            _ = try await RunPresetIntent(preset: PresetEntity(id: "gone", title: "Gone"), text: "x").perform()
        }
        await #expect(throws: HeadlessError.unavailable("gguf/acme/small")) {
            _ = try await AskWithModelIntent(text: "x", model: ModelEntity(local)).perform()
        }
        #expect(calls.all.isEmpty)
    }

    // MARK: Entities

    @Test func shortcutsListTheModelsThatCanAnswerNow() async throws {
        let calls = Calls()
        let notReady = testModel(id: "gguf/acme/not-downloaded", source: .gguf, installed: false)
        try await install([engine(.apple, [apple], calls: calls), engine(.gguf, [local, notReady], calls: calls),
                           engine(.anyrouter, [cloud], calls: calls)], selected: apple.id)
        let listed = try await ModelEntityQuery().suggestedEntities()
        #expect(listed.map(\.id) == [apple.id, local.id, cloud.id])
        #expect(listed.map(\.kind) == ["Apple Intelligence", "On this device", "AnyRouter"])
        let picked = try await ModelEntityQuery().entities(for: [local.id, notReady.id])
        #expect(picked.map(\.id) == [local.id])
        #expect(String(localized: listed[0].displayRepresentation.title) == "Apple Intelligence")
    }
}