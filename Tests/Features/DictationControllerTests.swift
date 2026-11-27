import Foundation
import SwiftUI
import Testing
@testable import AnyRouter

@MainActor
struct DictationControllerTests {
    private final class Field { var text = "" }
    private final class Ticker {
        var time = 0.0
        func tick() -> TimeInterval { time += 1; return time }
    }

    private struct Rig {
        let controller: DictationController
        let hub: VoiceHub
        let speech: FakeSpeechToText
        let field: Field
        let text: Binding<String>
    }

    private func rig(
        explain: Bool = false, permission: VoiceError? = nil, text: String = ""
    ) -> Rig {
        let speech = FakeSpeechToText()
        let field = Field()
        field.text = text
        let ticker = Ticker()
        let root = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString)")
        let hub = VoiceHub(
            settings: VoiceSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            downloader: VoiceModelDownloader(storage: VoiceModelStorage(root: root)),
            catalog: { [] }, systemSTT: { speech }, systemTTS: { FakeTextToSpeech() })
        let controller = DictationController(
            now: { ticker.tick() }, needsExplanation: { explain },
            requestPermissions: { if let permission { throw permission } })
        let binding = Binding(get: { field.text }, set: { field.text = $0 })
        return Rig(controller: controller, hub: hub, speech: speech, field: field, text: binding)
    }

    @Test func partialsFillTheFieldAfterWhatWasThereAndTheFinalEndsTheSession() async {
        let r = rig(text: "Note:")
        r.controller.begin(text: r.text, hub: r.hub)
        #expect(r.controller.phase == .preparing)
        await settle { r.speech.requests.count == 1 }
        r.speech.emit(.language(.vietnamese))
        r.speech.emit(.level(0.5))
        r.speech.emit(.partial("xin chào"))
        await settle { r.field.text == "Note: xin chào" }
        #expect(r.controller.phase == .listening)
        #expect(r.controller.language == .vietnamese)
        #expect(r.hub.settings.lastLanguage == .vietnamese)
        #expect(r.controller.level >= 0.5)
        r.speech.emit(.final("xin chào bạn"))
        r.speech.end()
        await settle { r.controller.phase == .idle }
        #expect(r.field.text == "Note: xin chào bạn")
        #expect(!r.controller.isActive)
    }

    @Test func theLanguageTheReaderForcedIsRequestedAndNothingElse() async {
        let r = rig()
        r.hub.settings.forcedLanguage = .vietnamese
        r.controller.begin(text: r.text, hub: r.hub)
        await settle { r.speech.requests.count == 1 }
        #expect(r.speech.requests[0].language == .vietnamese)
        r.controller.cancel()
    }

    @Test func withoutAForcedLanguageTheEngineGetsTheCandidates() async {
        let r = rig()
        r.hub.settings.lastLanguage = .vietnamese
        r.controller.begin(text: r.text, hub: r.hub)
        await settle { r.speech.requests.count == 1 }
        #expect(r.speech.requests[0].language == nil)
        #expect(r.speech.requests[0].candidates.first == .vietnamese)
        r.controller.cancel()
    }

    @Test func typingInTheFieldStopsListeningAndKeepsTheirText() async {
        let r = rig()
        r.controller.begin(text: r.text, hub: r.hub)
        await settle { r.speech.requests.count == 1 }
        r.speech.emit(.partial("hello"))
        await settle { r.field.text == "hello" }
        r.field.text = "typed by hand"
        r.speech.emit(.partial("hello again"))
        await settle { !r.controller.isActive }
        #expect(r.field.text == "typed by hand")
        #expect(r.speech.cancelCount == 1)
    }

    @Test func longSilenceAfterSpeechFinishesDictation() async {
        let r = rig()
        r.speech.finalOnFinish = "done"
        r.controller.begin(text: r.text, hub: r.hub)
        await settle { r.speech.requests.count == 1 }
        r.speech.emit(.level(0.6))
        for _ in 0..<4 { r.speech.emit(.level(0.02)) }
        await settle { r.speech.finishCount == 1 }
        await settle { r.controller.phase == .idle }
        #expect(r.field.text == "done")
    }

    @Test func tappingTheButtonWhileListeningFinishesAndKeepsTheWords() async {
        let r = rig()
        r.speech.finalOnFinish = "all the words"
        r.controller.begin(text: r.text, hub: r.hub)
        await settle { r.speech.requests.count == 1 }
        r.speech.emit(.level(0.4))
        await settle { r.controller.phase == .listening }
        r.controller.toggle(text: r.text, hub: r.hub)
        #expect(r.controller.phase == .finishing)
        r.controller.toggle(text: r.text, hub: r.hub)
        await settle { r.controller.phase == .idle }
        #expect(r.field.text == "all the words")
        #expect(r.speech.finishCount == 1)
    }

    @Test func theMicButtonStartsWhenIdle() async {
        let r = rig()
        r.controller.toggle(text: r.text, hub: r.hub)
        await settle { r.speech.requests.count == 1 }
        #expect(r.controller.isActive)
        r.controller.cancel()
        #expect(r.controller.phase == .idle && r.controller.level == 0)
    }

    @Test func theFirstUseShowsTheExplanationAndWaitsForContinue() async {
        let r = rig(explain: true)
        r.controller.begin(text: r.text, hub: r.hub)
        #expect(r.controller.showsExplanation && r.controller.phase == .idle)
        #expect(r.speech.requests.isEmpty)
        r.controller.confirmExplanation()
        #expect(!r.controller.showsExplanation)
        await settle { r.speech.requests.count == 1 }
        r.controller.cancel()
    }

    @Test func notNowStartsNothing() async {
        let r = rig(explain: true)
        r.controller.begin(text: r.text, hub: r.hub)
        r.controller.declineExplanation()
        #expect(!r.controller.showsExplanation && r.controller.phase == .idle)
        #expect(r.speech.requests.isEmpty)
    }

    @Test func aDeniedMicrophoneShowsAMessageAndStaysIdle() async {
        let r = rig(permission: .microphoneDenied)
        r.controller.begin(text: r.text, hub: r.hub)
        await settle { r.controller.errorMessage != nil }
        await settle { r.controller.phase == .idle }
        #expect(r.controller.errorMessage == VoiceError.microphoneDenied.errorDescription)
        #expect(r.speech.requests.isEmpty)
        r.controller.dismissError()
        #expect(r.controller.errorMessage == nil)
    }

    @Test func anEngineFailureEndsTheSessionWithItsMessage() async {
        let r = rig()
        r.controller.begin(text: r.text, hub: r.hub)
        await settle { r.speech.requests.count == 1 }
        r.speech.fail(VoiceError.languageUnavailable(.vietnamese))
        await settle { r.controller.phase == .idle }
        #expect(r.controller.errorMessage?.contains("Vietnamese") == true)
    }

    @Test func pickingALanguageWhileListeningRestartsInThatLanguageKeepingTheWords() async {
        let r = rig()
        r.controller.begin(text: r.text, hub: r.hub)
        await settle { r.speech.requests.count == 1 }
        r.speech.emit(.partial("hello"))
        await settle { r.field.text == "hello" }
        r.controller.choose(language: .vietnamese, hub: r.hub)
        await settle { r.speech.requests.count == 2 }
        #expect(r.speech.requests[1].language == .vietnamese)
        #expect(r.hub.settings.forcedLanguage == .vietnamese)
        #expect(r.speech.cancelCount == 1)
        r.speech.emit(.partial("xin chào"))
        await settle { r.field.text == "hello xin chào" }
        #expect(r.controller.isActive, "the end of the old session must not stop the new one")
        r.controller.cancel()
    }

    @Test func pickingALanguageWhileIdleOnlyRemembersIt() {
        let r = rig()
        r.controller.choose(language: .vietnamese, hub: r.hub)
        #expect(r.hub.settings.forcedLanguage == .vietnamese)
        r.controller.choose(language: nil, hub: r.hub)
        #expect(r.hub.settings.forcedLanguage == nil)
        #expect(r.speech.requests.isEmpty)
    }

    @Test func finishingWhileIdleDoesNothing() {
        let r = rig()
        r.controller.finish()
        #expect(r.controller.phase == .idle && r.speech.finishCount == 0)
    }
}
