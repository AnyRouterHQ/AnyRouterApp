import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct WhisperKitSpeechToTextTests {
    private struct Boom: Error, LocalizedError {
        var errorDescription: String? { "boom" }
    }

    /// Counts loads, and holds one until released.
    private final class Loads: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var isOpen = true

        var calls: Int { lock.withLock { count } }
        func hold() { lock.withLock { isOpen = false } }
        func release() { lock.withLock { isOpen = true } }

        func enter() async {
            lock.withLock { count += 1 }
            while !lock.withLock({ isOpen }) { try? await Task.sleep(for: .milliseconds(2)) }
        }
    }

    private let hello = [WhisperSegment(start: 0, end: 2, text: "<|0.00|> Xin chào<|2.00|>")]

    private func makeEngine(
        _ fake: FakeWhisperBackend, loads: Loads = Loads(), idle: Duration = .seconds(60)
    ) -> WhisperKitSpeechToText {
        WhisperKitSpeechToText(
            model: VoiceFixtures.model("whisper-test", detects: true),
            loader: { await loads.enter(); return fake },
            audio: .silent, idleTimeout: idle, pollInterval: .milliseconds(2))
    }

    private func collect(_ stream: AsyncThrowingStream<TranscriptEvent, Error>) -> Task<[TranscriptEvent], Error> {
        Task {
            var events: [TranscriptEvent] = []
            for try await event in stream { events.append(event) }
            return events
        }
    }

    private func withoutLevels(_ events: [TranscriptEvent]) -> [TranscriptEvent] {
        events.filter { if case .level = $0 { false } else { true } }
    }

    @Test func nothingLoadsUntilTheFirstDictation() async {
        let loads = Loads()
        let engine = makeEngine(FakeWhisperBackend(), loads: loads)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(loads.calls == 0)
        #expect(await engine.supports(.vietnamese))
    }

    @Test func detectsTheLanguageThenStreamsPartialsAndEndsWithTheWholeText() async throws {
        let fake = FakeWhisperBackend()
        fake.say(hello)
        let engine = makeEngine(fake)
        let events = collect(engine.start(SpeechRequest(language: nil)))
        await settle { !fake.transcribeCalls.isEmpty }
        await engine.finish()
        let all = try await events.value

        #expect(withoutLevels(all) == [.preparing(nil), .language(.vietnamese), .partial("Xin chào"), .final("Xin chào")])
        let firstLevel = try #require(all.firstIndex { if case .level = $0 { true } else { false } })
        let language = try #require(all.firstIndex(of: .language(.vietnamese)))
        #expect(firstLevel < language)
        #expect(fake.detectCalls == 1)
        #expect(fake.transcribeCalls.allSatisfy { $0.language == "vi" })
        #expect(fake.stopCount >= 1)
    }

    @Test func aLanguageInTheRequestSkipsDetection() async throws {
        let fake = FakeWhisperBackend()
        fake.say(hello, language: "vi")
        let engine = makeEngine(fake)
        let events = collect(engine.start(SpeechRequest(language: .english)))
        await settle { !fake.transcribeCalls.isEmpty }
        await engine.finish()
        let all = try await events.value

        #expect(withoutLevels(all) == [.preparing(nil), .language(.english), .partial("Xin chào"), .final("Xin chào")])
        #expect(fake.detectCalls == 0)
        #expect(fake.transcribeCalls.allSatisfy { $0.language == "en" })
    }

    @Test func silenceNeitherDetectsNorTranscribes() async throws {
        let fake = FakeWhisperBackend()
        fake.hear(seconds: 3, loud: false)
        fake.say(hello)
        let engine = makeEngine(fake)
        let events = collect(engine.start(SpeechRequest(language: nil)))
        await settle { fake.reads > 3 }
        await engine.finish()

        #expect(withoutLevels(try await events.value) == [.preparing(nil), .final("")])
        #expect(fake.detectCalls == 0)
        #expect(fake.transcribeCalls.isEmpty)
    }

    @Test func stoppingWhileTheModelLoadsEndsWithAnEmptyTranscriptAndNeverRecords() async throws {
        let fake = FakeWhisperBackend()
        let loads = Loads()
        loads.hold()
        let engine = makeEngine(fake, loads: loads)
        let events = collect(engine.start(SpeechRequest(language: nil)))
        await settle { loads.calls == 1 }
        let stopping = Task { await engine.finish() }
        try? await Task.sleep(for: .milliseconds(20))
        loads.release()
        await stopping.value

        #expect(try await events.value == [.preparing(nil), .final("")])
        #expect(fake.startCount == 0)
    }

    @Test func cancelEndsTheStreamWithoutAFinalAndTheEngineListensAgain() async throws {
        let fake = FakeWhisperBackend()
        fake.say(hello)
        let engine = makeEngine(fake)
        let first = collect(engine.start(SpeechRequest(language: nil)))
        await settle { !fake.transcribeCalls.isEmpty }
        engine.cancel()
        let heard = try await first.value
        #expect(!heard.contains(.final("Xin chào")))
        await settle { fake.stopCount >= 1 }
        #expect(fake.stopCount >= 1)

        let second = collect(engine.start(SpeechRequest(language: nil)))
        await settle { fake.startCount == 2 }
        await engine.finish()
        #expect(try await second.value.last == .final("Xin chào"))
    }

    @Test func aFailedPassBecomesTheStreamsError() async {
        let fake = FakeWhisperBackend()
        fake.failTranscribe(Boom())
        let engine = makeEngine(fake)
        let events = collect(engine.start(SpeechRequest(language: nil)))
        await #expect(throws: VoiceError.audioFailed("Speech recognition stopped: boom")) { try await events.value }
        await settle { fake.stopCount >= 1 }
        #expect(fake.stopCount >= 1)
    }

    @Test func aMicrophoneThatCannotStartBecomesTheStreamsError() async {
        let fake = FakeWhisperBackend()
        fake.failStart(WhisperFailure.microphoneUnavailable)
        let engine = makeEngine(fake)
        let events = collect(engine.start(SpeechRequest(language: nil)))
        await #expect(throws: VoiceError.audioFailed("The microphone could not start.")) { try await events.value }
    }

    @Test func theModelStaysLoadedBetweenDictations() async throws {
        let fake = FakeWhisperBackend()
        fake.say(hello)
        let loads = Loads()
        let engine = makeEngine(fake, loads: loads)
        for _ in 0..<2 {
            let events = collect(engine.start(SpeechRequest(language: .vietnamese)))
            await settle { fake.reads > 2 }
            await engine.finish()
            _ = try await events.value
        }
        #expect(loads.calls == 1)
        #expect(fake.unloadCount == 0)
    }

    @Test func anIdleModelIsUnloadedAndLoadsAgainOnTheNextDictation() async throws {
        let fake = FakeWhisperBackend()
        fake.say(hello)
        let loads = Loads()
        let engine = makeEngine(fake, loads: loads, idle: .milliseconds(20))
        let first = collect(engine.start(SpeechRequest(language: .vietnamese)))
        await settle { fake.reads > 2 }
        await engine.finish()
        _ = try await first.value
        await settle { fake.unloadCount == 1 }
        #expect(fake.unloadCount == 1)

        let second = collect(engine.start(SpeechRequest(language: .vietnamese)))
        await settle { loads.calls == 2 }
        await engine.finish()
        _ = try await second.value
        #expect(loads.calls == 2)
    }
}
