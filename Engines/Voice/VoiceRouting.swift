import Foundation

/// Which engine answers a request. The System engine is always the fallback; a downloaded model is used only when it is
/// installed, selected, and covers the language.
enum VoiceChoice: Equatable, Sendable {
    enum FallbackReason: Equatable, Sendable {
        case notInstalled
        case languageNotCovered(VoiceLanguage)
        case weakForLanguage(VoiceLanguage)
        case cannotDetectLanguage
    }

    case system(FallbackReason?)
    case model(VoiceModel)
}

enum VoiceRouting {
    /// `language` is nil for dictation that has not found the language yet. `selectedID` is nil or "system" for the System engine.
    static func choose(
        kind: VoiceModelKind, language: VoiceLanguage?, selectedID: String?, installed: Set<String>, catalog: [VoiceModel]
    ) -> VoiceChoice {
        guard let selectedID, let model = catalog.first(where: { $0.id == selectedID && $0.kind == kind }) else {
            return .system(nil)
        }
        guard installed.contains(model.id) else { return .system(.notInstalled) }
        guard let language else {
            return model.detectsLanguage ? .model(model) : .system(.cannotDetectLanguage)
        }
        guard model.supports(language) else { return .system(.languageNotCovered(language)) }
        guard !model.isWeak(for: language) else { return .system(.weakForLanguage(language)) }
        return .model(model)
    }

    /// Languages the user cares about that the model will hand to the System engine, for the line under a model row.
    static func handedToSystem(_ model: VoiceModel, wanted: [VoiceLanguage]) -> [VoiceLanguage] {
        wanted.filter { !model.supports($0) || model.isWeak(for: $0) }
    }

    /// The languages to try, in order, when dictation has to find the language itself: the one used last, the device
    /// languages, then English. At most `limit`, no repeats.
    static func candidates(lastUsed: VoiceLanguage?, deviceLanguages: [String], limit: Int = 2) -> [VoiceLanguage] {
        var seen: [VoiceLanguage] = []
        for language in [lastUsed].compactMap({ $0 }) + deviceLanguages.map(VoiceLanguage.init) + [.english] where !seen.contains(language) {
            seen.append(language)
        }
        return Array(seen.prefix(limit))
    }
}

/// A sentence to speak in the "Test voice" button, in the device language.
enum VoiceSamples {
    private static let sentences: [String: String] = [
        "en": "This is how your replies will sound.",
        "vi": "Đây là giọng đọc câu trả lời của bạn.",
        "es": "Así sonarán tus respuestas.",
        "fr": "Voici comment vos réponses seront lues.",
        "de": "So klingen deine Antworten.",
        "it": "Ecco come suoneranno le tue risposte.",
        "pt": "É assim que as suas respostas vão soar.",
        "ja": "これがあなたの返信の声です。",
        "zh": "这就是你的回复听起来的样子。",
        "ko": "이것이 답변의 목소리입니다.",
    ]

    static func sentence(for language: VoiceLanguage) -> String {
        sentences[language.code] ?? sentences["en", default: ""]
    }
}
