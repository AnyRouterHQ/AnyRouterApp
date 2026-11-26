import Foundation

enum DictationPhase: Equatable, Sendable {
    case idle
    /// Getting ready: loading a model or the system's language assets.
    case preparing
    case listening
    /// Stopped listening, waiting for the words in flight.
    case finishing
}

/// Quiet for a while after speech, or no speech at all for a while, means the reader is done.
struct SilenceDetector: Equatable, Sendable {
    /// `MicrophoneCapture.level` above this is speech. Room noise sits near zero.
    var speechLevel: Float = 0.25
    var silenceSeconds = 2.5
    var noSpeechSeconds = 8.0
    private var startedAt: TimeInterval?
    private var heardSpeech = false
    private var quietSince: TimeInterval?

    /// True when dictation should stop. `time` is any steady clock in seconds.
    mutating func observe(level: Float, at time: TimeInterval) -> Bool {
        let start = startedAt ?? time
        startedAt = start
        if level >= speechLevel {
            heardSpeech = true
            quietSince = nil
            return false
        }
        guard heardSpeech else { return time - start >= noSpeechSeconds }
        let since = quietSince ?? time
        quietSince = since
        return time - since >= silenceSeconds
    }
}

enum DictationRules {
    /// The text after a partial result: what was in the field when dictation began, then the transcript.
    static func merge(base: String, transcript: String) -> String {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if spoken.isEmpty { return base }
        if base.isEmpty || base.last?.isWhitespace == true { return base + spoken }
        return base + " " + spoken
    }

    /// The first time, the reader sees what listening means before the system asks.
    static func needsExplanation(microphone: VoicePermissions.Status, speechRecognition: VoicePermissions.Status) -> Bool {
        microphone == .notDetermined || speechRecognition == .notDetermined
    }

    /// The badge menu: English and Vietnamese, then the device's languages. Detection is the first row, outside this list.
    static func languageMenu(deviceLanguages: [String]) -> [VoiceLanguage] {
        var menu: [VoiceLanguage] = []
        for language in [VoiceLanguage.english, .vietnamese] + deviceLanguages.map(VoiceLanguage.init) where !menu.contains(language) {
            menu.append(language)
        }
        return menu
    }

    static func badgeTitle(forced: VoiceLanguage?, detected: VoiceLanguage?) -> String {
        (forced ?? detected)?.badge ?? "Auto"
    }

    static func statusText(_ phase: DictationPhase) -> String {
        switch phase {
        case .idle: ""
        case .preparing: "Getting ready…"
        case .listening: "Listening…"
        case .finishing: "Finishing…"
        }
    }
}
