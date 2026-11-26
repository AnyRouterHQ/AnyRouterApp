import Foundation

/// What a row in Settings › Local Models › Voice says and offers. No views here.
enum VoiceModelsRules {
    struct Row: Equatable {
        var detail: String
        /// The line under the detail: fit, or which languages go to the System engine.
        var note: String?
        var isDefault: Bool
        var isRecommended: Bool
        /// Tapping the row makes it the default: only a model that is on the device can be.
        var canSelect: Bool
        var canGet: Bool
        var canDelete: Bool
    }

    static let speechFooter = "Dictation uses the System engine unless you pick a model here. With a Whisper model the language is found from the audio itself; with the System engine AnyRouter tries your device languages and English, so pick a language in the composer if it guesses wrong."
    static let voiceFooter = "A model reads only the languages it lists; every other language uses the System voice. Better System voices are in Settings, Accessibility, Spoken Content, Voices."

    static func row(
        _ model: VoiceModel, state: ModelDownloadState, verdict: VoiceFit.Verdict, isDefault: Bool, isRecommended: Bool,
        wanted: [VoiceLanguage]
    ) -> Row {
        let installed = state == .installed
        return Row(
            detail: detail(model), note: note(model, state: state, verdict: verdict, wanted: wanted),
            isDefault: isDefault, isRecommended: isRecommended && !installed, canSelect: installed && !isDefault,
            canGet: !model.isSystem && verdict != .wontFit && state.canStart,
            canDelete: !model.isSystem && (installed || state.isFailed))
    }

    /// "99 languages · 217 MB · MIT".
    static func detail(_ model: VoiceModel) -> String {
        if model.isSystem { return model.summary ?? "Built in" }
        return [model.languageSummary, FitFormat.gigabytes(model.sizeBytes), model.license].joined(separator: " · ")
    }

    static func note(_ model: VoiceModel, state: ModelDownloadState, verdict: VoiceFit.Verdict, wanted: [VoiceLanguage]) -> String? {
        if case .failed(let message) = state { return message }
        guard !model.isSystem else { return nil }
        let handed = VoiceRouting.handedToSystem(model, wanted: wanted)
        if !handed.isEmpty, state == .installed || verdict != .wontFit {
            return "Uses the System \(model.kind == .stt ? "engine" : "voice") for " + handed.map(\.name).joined(separator: ", ")
        }
        return verdict == .runsWell ? nil : verdict.title
    }

    /// The languages to mention: English, Vietnamese and the device's own.
    static func wantedLanguages(deviceLanguages: [String]) -> [VoiceLanguage] {
        DictationRules.languageMenu(deviceLanguages: deviceLanguages)
    }
}

extension ModelDownloadState {
    var canStart: Bool {
        switch self {
        case .notInstalled, .failed: true
        default: false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
