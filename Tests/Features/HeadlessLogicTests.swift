import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct HeadlessLogicTests {
    private let apple = testModel(id: "apple/foundation", source: .apple)
    private let local = testModel(id: "gguf/acme/small", source: .gguf)
    private let cloud = testModel(id: "anyrouter/auto", source: .anyrouter)

    @Test func anAskedForModelIsUsedOrTheRunFails() throws {
        let models = [apple, local, cloud]
        #expect(try HeadlessLogic.resolve(requestedID: local.id, models: models, fallback: apple, isOnline: false).id == local.id)
        #expect(try HeadlessLogic.resolve(requestedID: cloud.id, models: models, fallback: apple, isOnline: true).id == cloud.id)
        #expect(throws: HeadlessError.unavailable("gone")) {
            try HeadlessLogic.resolve(requestedID: "gone", models: models, fallback: apple, isOnline: true)
        }
        let notReady = testModel(id: "gguf/acme/x", source: .gguf, installed: false)
        #expect(throws: HeadlessError.unavailable("gguf/acme/x")) {
            try HeadlessLogic.resolve(requestedID: notReady.id, models: models + [notReady], fallback: apple, isOnline: true)
        }
        #expect(throws: HeadlessError.self) {
            try HeadlessLogic.resolve(requestedID: cloud.id, models: models, fallback: apple, isOnline: false)
        }
    }

    @Test func theDefaultAnswersUnlessOfflineAndInTheCloud() throws {
        #expect(try HeadlessLogic.resolve(requestedID: nil, models: [apple, cloud], fallback: cloud, isOnline: true).id == cloud.id)
        #expect(try HeadlessLogic.resolve(requestedID: nil, models: [apple, cloud], fallback: local, isOnline: false).id == local.id)
        #expect(try HeadlessLogic.resolve(requestedID: nil, models: [apple, cloud], fallback: cloud, isOnline: false).id == apple.id)
        #expect(throws: HeadlessError.noModel) {
            try HeadlessLogic.resolve(requestedID: nil, models: [apple], fallback: nil, isOnline: true)
        }
        #expect(throws: HeadlessError.self) {
            try HeadlessLogic.resolve(requestedID: nil, models: [cloud], fallback: cloud, isOnline: false)
        }
    }

    @Test func picksApplyToTheOptionsThePresetHas() throws {
        let items = try PresetStore.bundled(bundle: Bundle(for: PresetStore.self))
        let reply = try #require(items.first { $0.id == "reply-to-this" })
        let prompt = HeadlessLogic.prompt(preset: reply, choices: ["tone": "formal", "language": "gone", "colour": "red"], text: "Hi")
        #expect(prompt.contains("Tone: formal and professional."))
        #expect(prompt.contains("Language: the same language as the message."), "an unknown choice keeps the default")
        #expect(prompt.hasSuffix("Message:\nHi"))

        let plain = PromptPreset(id: "p", title: "T", prompt: "Do it:\n", category: .write, symbol: "sparkles")
        #expect(HeadlessLogic.prompt(preset: plain, choices: ["tone": "formal"], text: "x") == "Do it:\nx")
    }

    @Test func textIsTrimmedAndEmptyTextIsAnError() throws {
        #expect(try HeadlessLogic.cleaned("  a \n") == "a")
        #expect(throws: HeadlessError.noText) { try HeadlessLogic.cleaned(" \n ") }
    }

    @Test func everyErrorSaysWhatToDo() {
        let errors: [HeadlessError] = [
            .noText, .unknownPreset, .noModel, .unavailable("m"), .offline("You are offline."),
            .failed(model: "M", reason: "busy"), .empty(model: "M"),
        ]
        for error in errors {
            #expect(!error.message.isEmpty)
            #expect(error.errorDescription == error.message)
            #expect(String(localized: error.localizedStringResource) == error.message)
        }
        #expect(HeadlessError.failed(model: "M", reason: "busy").message == "M could not answer: busy")
        #expect(HeadlessError.offline("You are offline.").message == "You are offline.")
    }
}
