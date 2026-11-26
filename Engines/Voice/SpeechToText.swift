import Foundation

/// What a listening session reports, in the order it happens: `preparing`, then `language`, `level` and `partial` many times, then `final`.
enum TranscriptEvent: Equatable, Sendable {
    /// The engine is getting ready. The fraction is a model download; nil when unknown.
    case preparing(Double?)
    /// Microphone level, 0 to 1.
    case level(Float)
    /// The language the engine settled on: the one asked for, or the one it detected.
    case language(VoiceLanguage)
    /// The whole transcript so far. Each one replaces the one before.
    case partial(String)
    /// The whole transcript, once, when the session ends.
    case final(String)
}

struct SpeechRequest: Equatable, Sendable {
    /// Nil asks the engine to find the language.
    var language: VoiceLanguage?
    /// Languages worth trying when `language` is nil and the engine cannot detect it from audio.
    var candidates: [VoiceLanguage] = []
}

enum VoiceError: Error, Equatable, LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case languageUnavailable(VoiceLanguage)
    case audioFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "AnyRouter cannot use the microphone. Turn it on in Settings."
        case .speechRecognitionDenied: "AnyRouter cannot use speech recognition. Turn it on in Settings."
        case .languageUnavailable(let language): "\(language.name) is not available for voice on this device."
        case .audioFailed(let message): message
        }
    }
}

/// Real-time dictation. The System engine is always there; a downloaded model is another conformance.
@MainActor
protocol SpeechToText: AnyObject {
    var id: String { get }
    /// Whether this engine can listen for the language on this device now.
    func supports(_ language: VoiceLanguage) async -> Bool
    /// Starts the microphone and reports events. Ending the loop that reads the stream stops the session.
    func start(_ request: SpeechRequest) -> AsyncThrowingStream<TranscriptEvent, Error>
    /// Stops the microphone, finishes the words in flight, and lets the stream deliver `final`.
    func finish() async
    /// Stops now and drops what was heard.
    func cancel()
}
