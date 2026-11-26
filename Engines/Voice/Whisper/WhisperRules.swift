import Foundation

/// One phrase Whisper heard, with its place in the recording in seconds.
struct WhisperSegment: Equatable, Sendable {
    var start: Float
    var end: Float
    var text: String
}

/// The transcript of one dictation as Whisper reports it. Each pass over the audio returns the phrases after the last
/// confirmed one. All but the last two are confirmed (later passes start after them); the last two can still change as
/// more speech arrives, so they stay tentative.
struct WhisperTranscript: Equatable, Sendable {
    static let tentativeTail = 2

    private(set) var confirmed: [WhisperSegment] = []
    private(set) var tentative: [WhisperSegment] = []

    /// Where the next pass starts, in seconds.
    var confirmedEnd: Float { confirmed.last?.end ?? 0 }

    /// Confirmed phrases, then the tentative ones.
    var text: String { Self.join(confirmed + tentative) }

    /// Takes the phrases of one pass. With `isFinal`, the recording is over and every phrase is confirmed.
    mutating func apply(_ segments: [WhisperSegment], isFinal: Bool = false) {
        let heard = segments.filter { !Self.clean($0.text).isEmpty }
        let keep = isFinal ? 0 : Self.tentativeTail
        let settled = heard.count > keep ? heard.count - keep : 0
        let previousEnd = confirmedEnd
        confirmed += heard.prefix(settled).filter { $0.end > previousEnd }
        let end = confirmedEnd
        tentative = heard.dropFirst(settled).filter { $0.end > end }
    }

    /// Ends the session without another pass: what was tentative becomes confirmed.
    mutating func finish() {
        confirmed += tentative
        tentative = []
    }

    /// Whisper marks timestamps and languages with `<|...|>` tokens; they are not words.
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|>]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func join(_ segments: [WhisperSegment]) -> String {
        segments.map { clean($0.text) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// When to ask Whisper which language is spoken: once, after enough speech, and never when the user chose one.
struct WhisperLanguageTrigger: Equatable, Sendable {
    /// Seconds of speech before a guess is worth making.
    static let voicedSecondsNeeded: Float = 1.5
    /// A short dictation that ended early still gets a guess from this much speech.
    static let voicedSecondsWhenEnding: Float = 0.3

    private(set) var language: VoiceLanguage?

    /// `forced` is the language in the request, nil to detect.
    init(forced: VoiceLanguage?) { language = forced }

    func shouldDetect(voicedSeconds: Float, isEnding: Bool = false) -> Bool {
        guard language == nil else { return false }
        return voicedSeconds >= (isEnding ? Self.voicedSecondsWhenEnding : Self.voicedSecondsNeeded)
    }

    mutating func settle(_ detected: VoiceLanguage) {
        if language == nil { language = detected }
    }
}

/// What the recorded audio says about speech, from the energy list Whisper keeps (one value per short buffer).
enum WhisperVoice {
    static let sampleRate: Float = 16_000
    /// Relative energy above this is speech (the value WhisperKit's own streaming uses).
    static let silenceThreshold: Float = 0.3

    static func seconds(samples: Int) -> Float { Float(samples) / sampleRate }

    /// Seconds of the recording that sat in loud buffers. Buffers are the same length, so each counts the same share.
    static func voicedSeconds(energy: [Float], sampleCount: Int) -> Float {
        guard !energy.isEmpty, sampleCount > 0 else { return 0 }
        let voiced = energy.reduce(0) { $0 + ($1 > silenceThreshold ? 1 : 0) }
        return seconds(samples: sampleCount) * Float(voiced) / Float(energy.count)
    }

    /// Whether the buffers that arrived since `from` samples contain speech.
    static func hasSpeech(energy: [Float], sampleCount: Int, since from: Int) -> Bool {
        guard !energy.isEmpty, sampleCount > from else { return false }
        let share = Float(sampleCount - from) / Float(sampleCount)
        let count = max(1, Int((Float(energy.count) * share).rounded(.up)))
        return energy.suffix(count).contains { $0 > silenceThreshold }
    }
}

/// How often a live pass over the audio is worth its cost.
enum WhisperPacing {
    /// New audio needed before another pass.
    static let newSecondsNeeded: Float = 1

    static func shouldTranscribe(energy: [Float], sampleCount: Int, transcribedSamples: Int) -> Bool {
        WhisperVoice.seconds(samples: sampleCount - transcribedSamples) > newSecondsNeeded
            && WhisperVoice.hasSpeech(energy: energy, sampleCount: sampleCount, since: transcribedSamples)
    }
}

/// Whisper's language codes and ours differ in two places: it still says "jw" for Javanese.
enum WhisperLanguages {
    private static let legacy = ["jw": "jv"]

    static func voiceLanguage(fromWhisper code: String) -> VoiceLanguage {
        VoiceLanguage(legacy[code] ?? code)
    }

    static func whisperCode(for language: VoiceLanguage) -> String {
        legacy.first { $0.value == language.code }?.key ?? language.code
    }
}

/// What goes wrong inside the Whisper backend, before it is shown to the user.
enum WhisperFailure: Error, Equatable {
    case modelUnavailable
    case microphoneUnavailable
    case failed(String)

    var voiceError: VoiceError {
        switch self {
        case .modelUnavailable: .audioFailed("The speech model could not be loaded. Delete it in Settings and download it again.")
        case .microphoneUnavailable: .audioFailed("The microphone could not start.")
        case .failed(let detail): .audioFailed("Speech recognition stopped: \(detail)")
        }
    }

    static func map(_ error: any Error) -> VoiceError {
        if let error = error as? VoiceError { return error }
        if let error = error as? WhisperFailure { return error.voiceError }
        return WhisperFailure.failed(error.localizedDescription).voiceError
    }
}
