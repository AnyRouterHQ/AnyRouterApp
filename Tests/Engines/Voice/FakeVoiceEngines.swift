import Foundation
@testable import AnyRouter

/// A speech engine the test drives by hand.
@MainActor
final class FakeSpeechToText: SpeechToText {
    let id: String
    var supported: Set<VoiceLanguage>
    var finalOnFinish = ""
    private(set) var requests: [SpeechRequest] = []
    private(set) var finishCount = 0
    private(set) var cancelCount = 0
    private var continuation: AsyncThrowingStream<TranscriptEvent, Error>.Continuation?

    init(id: String = "fake", supported: Set<VoiceLanguage> = [.english, .vietnamese]) {
        self.id = id
        self.supported = supported
    }

    func supports(_ language: VoiceLanguage) async -> Bool { supported.contains(language) }

    func start(_ request: SpeechRequest) -> AsyncThrowingStream<TranscriptEvent, Error> {
        requests.append(request)
        let (stream, continuation) = AsyncThrowingStream<TranscriptEvent, Error>.makeStream()
        self.continuation = continuation
        return stream
    }

    func finish() async {
        finishCount += 1
        continuation?.yield(.final(finalOnFinish))
        continuation?.finish()
    }

    func cancel() {
        cancelCount += 1
        continuation?.finish()
    }

    func emit(_ event: TranscriptEvent) { continuation?.yield(event) }
    func end() { continuation?.finish() }
    func fail(_ error: Error) { continuation?.finish(throwing: error) }
}

/// A speech synthesizer that records what it was asked to say. With `holds`, `speak` waits until `release` or `stop`.
@MainActor
final class FakeTextToSpeech: TextToSpeech {
    let id: String
    var supported: Set<VoiceLanguage>
    var holds = false
    private(set) var spoken: [(text: String, language: VoiceLanguage)] = []
    private(set) var stopCount = 0
    private var waiting: CheckedContinuation<Void, Never>?

    init(id: String = "fake", supported: Set<VoiceLanguage> = [.english, .vietnamese]) {
        self.id = id
        self.supported = supported
    }

    func supports(_ language: VoiceLanguage) async -> Bool { supported.contains(language) }

    func speak(_ text: String, language: VoiceLanguage) async throws {
        guard supported.contains(language) else { throw VoiceError.languageUnavailable(language) }
        spoken.append((text, language))
        if holds { await withCheckedContinuation { waiting = $0 } }
    }

    func stop() {
        stopCount += 1
        release()
    }

    func release() {
        waiting?.resume()
        waiting = nil
    }
}

@MainActor
func settle(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<1000 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}
