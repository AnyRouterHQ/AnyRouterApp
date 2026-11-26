import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct TTSKitTextToSpeechTests {
    private struct Boom: Error, LocalizedError {
        var errorDescription: String? { "boom" }
    }

    /// Counts loads, can hold one until released, and can fail the first ones.
    private final class Loads: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var isOpen = true
        private var failuresLeft = 0

        var calls: Int { lock.withLock { count } }
        func hold() { lock.withLock { isOpen = false } }
        func release() { lock.withLock { isOpen = true } }
        func failFirst(_ times: Int) { lock.withLock { failuresLeft = times } }

        func enter() async throws {
            let shouldFail = lock.withLock { () -> Bool in
                count += 1
                if failuresLeft > 0 { failuresLeft -= 1; return true }
                return false
            }
            while !lock.withLock({ isOpen }) { try? await Task.sleep(for: .milliseconds(2)) }
            if shouldFail { throw Boom() }
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func bump() { lock.withLock { value += 1 } }
    }

    private let model = VoiceFixtures.model(
        "ttskit-test", kind: .tts, languages: ["en", "de", "ja", "vi"])

    private func makeEngine(
        _ fake: FakeTTSBackend, loads: Loads = Loads(), idle: Duration = .seconds(60),
        activate: @escaping @MainActor () throws -> Void = {}
    ) -> TTSKitTextToSpeech {
        TTSKitTextToSpeech(
            model: model, loader: { try await loads.enter(); return fake }, activateAudio: activate, idleTimeout: idle)
    }

    @Test func nothingLoadsUntilTheFirstSentence() async {
        let loads = Loads()
        let engine = makeEngine(FakeTTSBackend(), loads: loads)
        _ = await engine.supports(.english)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(loads.calls == 0)
        #expect(engine.id == "ttskit-test")
    }

    @Test func itSpeaksOnlyLanguagesTheModelListsAndTTSKitHas() async {
        let engine = makeEngine(FakeTTSBackend())
        #expect(await engine.supports(.english))
        #expect(await engine.supports(VoiceLanguage("de")))
        #expect(await !engine.supports(.vietnamese), "TTSKit has no Vietnamese even when a list names it")
        #expect(await !engine.supports(VoiceLanguage("fr")), "the model's list narrows what TTSKit could say")
        #expect(await !engine.supports(VoiceLanguage("th")))
    }

    @Test func aSentenceGoesToTheBackendInTheMappedLanguageAndReturnsAfterItPlayed() async throws {
        let fake = FakeTTSBackend()
        let activations = Counter()
        let engine = makeEngine(fake, activate: { activations.bump() })
        try await engine.speak("  Guten Tag.\n", language: VoiceLanguage("de-DE"))
        #expect(fake.calls == [.init(text: "Guten Tag.", language: .german)])
        #expect(fake.finished == 1, "speak returns only after the backend finished playing")
        #expect(activations.count == 1)
        try await engine.speak("Hello", language: .english)
        #expect(fake.calls.map(\.language) == [.german, .english])
    }

    @Test func aLanguageItDoesNotHaveIsRefusedWithoutLoadingAnything() async {
        let loads = Loads()
        let engine = makeEngine(FakeTTSBackend(), loads: loads)
        await #expect(throws: VoiceError.languageUnavailable(.vietnamese)) { try await engine.speak("Xin chào", language: .vietnamese) }
        await #expect(throws: VoiceError.languageUnavailable(VoiceLanguage("fr"))) {
            try await engine.speak("Bonjour", language: VoiceLanguage("fr"))
        }
        #expect(loads.calls == 0)
    }

    @Test func textWithNothingToSayIsSkipped() async throws {
        let loads = Loads()
        let fake = FakeTTSBackend()
        let engine = makeEngine(fake, loads: loads)
        try await engine.speak(" \n ", language: .english)
        #expect(loads.calls == 0 && fake.calls.isEmpty)
    }

    @Test func stopCutsTheSentenceAndTheSpeakReturns() async throws {
        let fake = FakeTTSBackend()
        fake.hold()
        let engine = makeEngine(fake)
        let speaking = Task { try await engine.speak("Hello", language: .english) }
        await settle { fake.calls.count == 1 }
        engine.stop()
        try await speaking.value
        #expect(fake.finished == 0, "it was cut, not played to the end")
    }

    @Test func cancellingTheCallerStopsItToo() async throws {
        let fake = FakeTTSBackend()
        fake.hold()
        let engine = makeEngine(fake)
        let speaking = Task { try await engine.speak("Hello", language: .english) }
        await settle { fake.calls.count == 1 }
        speaking.cancel()
        try await speaking.value
        #expect(fake.finished == 0)
    }

    @Test func aNewSentenceStopsTheOldOneAndWaitsForItBeforeUsingTheSpeaker() async throws {
        let fake = FakeTTSBackend()
        fake.hold()
        let engine = makeEngine(fake)
        let first = Task { try await engine.speak("one", language: .english) }
        await settle { fake.calls.count == 1 }
        let second = Task { try await engine.speak("two", language: .english) }
        await settle { fake.calls.count == 2 }
        fake.release()
        try await first.value
        try await second.value
        #expect(fake.calls.map(\.text) == ["one", "two"])
        #expect(!fake.overlapped, "the audio output belongs to one sentence at a time")
        #expect(fake.finished == 1, "only the second one played to the end")
    }

    @Test func stopWhileTheModelLoadsPlaysNothingOnceItIsLoaded() async throws {
        let loads = Loads()
        loads.hold()
        let fake = FakeTTSBackend()
        let engine = makeEngine(fake, loads: loads)
        let speaking = Task { try await engine.speak("Hello", language: .english) }
        await settle { loads.calls == 1 }
        engine.stop()
        loads.release()
        try await speaking.value
        #expect(fake.calls.isEmpty)
        try await engine.speak("Again", language: .english)
        #expect(fake.calls.map(\.text) == ["Again"])
        #expect(loads.calls == 1, "the load that was already running is reused")
    }

    @Test func aBackendFailureBecomesAVoiceError() async {
        let fake = FakeTTSBackend()
        fake.fail(TTSFailure.modelUnavailable)
        let engine = makeEngine(fake)
        await #expect(throws: TTSFailure.modelUnavailable.voiceError) { try await engine.speak("Hello", language: .english) }
        fake.fail(Boom())
        do {
            try await engine.speak("Hello", language: .english)
            Issue.record("expected a failure")
        } catch {
            #expect((error as? VoiceError)?.errorDescription?.contains("boom") == true)
        }
    }

    @Test func aFailedLoadIsReportedAndTriedAgainOnTheNextSentence() async throws {
        let loads = Loads()
        loads.failFirst(1)
        let fake = FakeTTSBackend()
        let engine = makeEngine(fake, loads: loads)
        await #expect(throws: VoiceError.self) { try await engine.speak("Hello", language: .english) }
        try await engine.speak("Hello", language: .english)
        #expect(loads.calls == 2)
        #expect(fake.finished == 1)
    }

    @Test func aFailedLoadDuringAStopIsNotKeptEither() async throws {
        let loads = Loads()
        loads.failFirst(1)
        loads.hold()
        let fake = FakeTTSBackend()
        let engine = makeEngine(fake, loads: loads)
        let speaking = Task { try await engine.speak("Hello", language: .english) }
        await settle { loads.calls == 1 }
        engine.stop()
        loads.release()
        try await speaking.value
        try await Task.sleep(for: .milliseconds(20))
        try await engine.speak("Hello", language: .english)
        #expect(fake.finished == 1)
    }

    @Test func anAudioSessionThatWillNotStartIsReported() async {
        struct NoSession: Error, LocalizedError { var errorDescription: String? { "busy" } }
        let fake = FakeTTSBackend()
        let engine = makeEngine(fake, activate: { throw NoSession() })
        do {
            try await engine.speak("Hello", language: .english)
            Issue.record("expected a failure")
        } catch {
            #expect((error as? VoiceError)?.errorDescription?.contains("busy") == true)
        }
        #expect(fake.calls.isEmpty)
    }

    @Test func anIdleModelIsUnloadedAndLoadsAgainOnTheNextSentence() async throws {
        let loads = Loads()
        let fake = FakeTTSBackend()
        let engine = makeEngine(fake, loads: loads, idle: .milliseconds(20))
        try await engine.speak("Hello", language: .english)
        await settle { fake.unloads == 1 }
        #expect(fake.unloads == 1)
        try await engine.speak("Hello again", language: .english)
        #expect(loads.calls == 2)
        #expect(fake.calls.count == 2)
    }

    @Test func aModelStaysLoadedWhileRepliesKeepComing() async throws {
        let loads = Loads()
        let fake = FakeTTSBackend()
        let engine = makeEngine(fake, loads: loads, idle: .milliseconds(400))
        for _ in 0..<3 {
            try await engine.speak("Hello", language: .english)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(loads.calls == 1)
        #expect(fake.unloads == 0)
    }

    @Test func aModelIsNotUnloadedWhileASentenceIsPlaying() async throws {
        let fake = FakeTTSBackend()
        fake.hold()
        let engine = makeEngine(fake, idle: .milliseconds(10))
        let speaking = Task { try await engine.speak("Hello", language: .english) }
        await settle { fake.calls.count == 1 }
        try await Task.sleep(for: .milliseconds(60))
        #expect(fake.unloads == 0)
        fake.release()
        try await speaking.value
    }
}
