import Foundation

/// The languages Qwen3-TTS speaks, with the speaker used for each. Raw values are TTSKit's own language names
/// (`Qwen3Language` in argmax-oss-swift 1.1.1). Vietnamese is not here on purpose: the app hands it to the System voice.
/// The catalog entry's `languages` list is tested to match this one.
enum TTSKitLanguage: String, CaseIterable, Sendable {
    case english, chinese, japanese, korean, german, french, russian, portuguese, spanish, italian

    init?(_ language: VoiceLanguage) {
        guard let match = Self.allCases.first(where: { $0.code == language.code }) else { return nil }
        self = match
    }

    var code: String {
        switch self {
        case .english: "en"
        case .chinese: "zh"
        case .japanese: "ja"
        case .korean: "ko"
        case .german: "de"
        case .french: "fr"
        case .russian: "ru"
        case .portuguese: "pt"
        case .spanish: "es"
        case .italian: "it"
        }
    }

    /// A `Qwen3Speaker` raw value. Each language gets its native speaker where the model has one; the model says every
    /// speaker can speak every language, so the other languages use the English one. How those sound is not measured.
    var speaker: String {
        switch self {
        case .chinese: "vivian"
        case .japanese: "ono-anna"
        case .korean: "sohee"
        default: "ryan"
        }
    }
}

/// What goes wrong inside the TTSKit backend, before it is shown to the user.
enum TTSFailure: Error, Equatable {
    case modelUnavailable
    case audioFailed(String)
    case failed(String)

    var voiceError: VoiceError {
        switch self {
        case .modelUnavailable: .audioFailed("The voice model could not be loaded. Delete it in Settings and download it again.")
        case .audioFailed(let detail): .audioFailed("The voice could not play: \(detail)")
        case .failed(let detail): .audioFailed("Speaking stopped: \(detail)")
        }
    }

    static func map(_ error: any Error) -> VoiceError {
        if let error = error as? VoiceError { return error }
        if let error = error as? TTSFailure { return error.voiceError }
        return TTSFailure.failed(error.localizedDescription).voiceError
    }
}
