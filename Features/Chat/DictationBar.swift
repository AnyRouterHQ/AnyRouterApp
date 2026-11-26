import SwiftUI

/// Above the field while dictating: the language badge (tap to force a language), a level meter, the state, and cancel.
struct DictationBar: View {
    let dictation: DictationController
    let hub: VoiceHub

    var body: some View {
        HStack(spacing: 8) {
            languageMenu
            // A symbol with a variable value is the system's own meter: more of the waves draw as the level rises.
            Image(systemName: "waveform", variableValue: Double(dictation.level))
                .imageScale(.large)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(DictationRules.statusText(dictation.phase))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dictation.status")
            Spacer(minLength: 0)
            Button(role: .close) { dictation.cancel() }
                .accessibilityLabel("Cancel dictation")
                .accessibilityIdentifier("dictation.cancel")
        }
        .padding(.horizontal, 4)
        .accessibilityIdentifier("dictation.bar")
    }

    private var languageMenu: some View {
        Menu {
            Picker("Language", selection: Binding(
                get: { hub.settings.forcedLanguage },
                set: { dictation.choose(language: $0, hub: hub) }
            )) {
                Text("Detect language").tag(VoiceLanguage?.none)
                ForEach(DictationRules.languageMenu(deviceLanguages: Locale.preferredLanguages), id: \.self) { language in
                    Text(language.name).tag(Optional(language))
                }
            }
        } label: {
            Text(DictationRules.badgeTitle(forced: hub.settings.forcedLanguage, detected: dictation.language))
                .font(.caption.weight(.semibold))
                .frame(minWidth: 32)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .frame(minHeight: 44)
        .accessibilityLabel("Dictation language")
        .accessibilityIdentifier("dictation.language")
    }
}

/// Shown once, before the system asks for the microphone: what listening means and where the audio goes.
struct VoicePermissionSheet: View {
    var onContinue: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Dictate on this device")
                .font(.title2.bold())
            Text("AnyRouter listens through the microphone and turns your speech into text on this device. The audio is not sent to a server by AnyRouter. iOS asks for the microphone and for speech recognition next.")
                .font(.body)
                .multilineTextAlignment(.center)
            Button(action: onContinue) {
                Text("Continue").prominentLabel().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("voice.permission.continue")
            Button("Not Now", action: onNotNow)
                .frame(minHeight: 44)
                .accessibilityIdentifier("voice.permission.notNow")
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
