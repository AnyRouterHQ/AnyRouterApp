import SwiftUI

/// Settings › Local Models › Voice: the engines that listen (speech to text) and speak (text to speech). The System rows
/// are always there. A downloaded model is used only when it is installed, selected, and covers the language.
struct VoiceModelsScreen: View {
    @Environment(AppState.self) private var app
    @State private var sampleIsPlaying = false

    private var hub: VoiceHub { app.voice }
    private var wanted: [VoiceLanguage] { VoiceModelsRules.wantedLanguages(deviceLanguages: Locale.preferredLanguages) }

    var body: some View {
        List {
            modelSection(.stt, title: "Speech to text", footer: VoiceModelsRules.speechFooter)
            dictationSection
            modelSection(.tts, title: "Text to speech", footer: VoiceModelsRules.voiceFooter)
            speakingSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("voice.list")
        .onDisappear { if sampleIsPlaying { hub.textToSpeech(for: VoiceLanguage.device).engine.stop() } }
    }

    // MARK: Sections

    private func modelSection(_ kind: VoiceModelKind, title: String, footer: String) -> some View {
        let recommended = hub.recommended(kind)
        return Section {
            ForEach(hub.models(kind)) { model in
                VoiceModelRow(model: model, hub: hub, wanted: wanted, isRecommended: model.id == recommended?.id)
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
        .accessibilityIdentifier("voice.section.\(kind.rawValue)")
    }

    private var dictationSection: some View {
        Section {
            Picker("Dictation language", selection: Binding(
                get: { hub.settings.forcedLanguage },
                set: { hub.settings.forcedLanguage = $0 }
            )) {
                Text("Detect").tag(VoiceLanguage?.none)
                ForEach(DictationRules.languageMenu(deviceLanguages: Locale.preferredLanguages), id: \.self) { language in
                    Text(language.name).tag(Optional(language))
                }
            }
            .accessibilityIdentifier("voice.dictationLanguage")
        } footer: {
            Text("The badge above the composer while you dictate changes the same setting.")
        }
    }

    private var speakingSection: some View {
        Section {
            Toggle("Read replies aloud", isOn: Binding(
                get: { hub.settings.readRepliesAloud },
                set: { hub.settings.readRepliesAloud = $0 }
            ))
            .accessibilityIdentifier("voice.readAloud")
            Button(sampleIsPlaying ? "Stop" : "Test voice", systemImage: sampleIsPlaying ? "stop.circle" : "speaker.wave.2") {
                Task { await toggleSample() }
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("voice.test")
        } footer: {
            Text("The speaker button under a reply reads that reply whatever this switch says.")
        }
    }

    /// Speaks a sample in the device language with the engine that would read a reply in that language.
    private func toggleSample() async {
        let speaker = app.speaker
        if sampleIsPlaying {
            hub.textToSpeech(for: VoiceLanguage.device).engine.stop()
            return
        }
        speaker.stop()
        let language = VoiceLanguage.device
        sampleIsPlaying = true
        defer { sampleIsPlaying = false }
        let engine = hub.textToSpeech(for: language).engine
        do {
            try await engine.speak(VoiceSamples.sentence(for: language), language: language)
        } catch {
            if case VoiceError.languageUnavailable(let missing) = error {
                speaker.setNotice(ReplySpeaker.missingVoiceNotice(missing))
            } else {
                speaker.setNotice(error.localizedDescription)
            }
        }
    }
}

/// One engine or model as a `ListRow`: name, languages, size and licence, how it fits, and Get, progress or the check
/// mark. A wrapper because it owns the delete confirmation and the select and download actions.
private struct VoiceModelRow: View {
    let model: VoiceModel
    let hub: VoiceHub
    let wanted: [VoiceLanguage]
    let isRecommended: Bool
    @State private var confirmsDelete = false

    private var state: ModelDownloadState { hub.downloader.state(for: model) }
    @ScaledMetric(relativeTo: .body) private var logoSize: CGFloat = 22

    var body: some View {
        let current = state
        let row = VoiceModelsRules.row(
            model, state: current, verdict: VoiceFit.verdict(model, memory: .current()), isDefault: hub.isSelected(model),
            isRecommended: isRecommended, wanted: wanted)
        HStack(spacing: 8) {
            Button { hub.select(model) } label: {
                ListRow(model.title, secondary: secondary(row, failed: current.isFailed)) {
                    ModelLogo(brand: .symbol(model.isSystem ? "iphone" : "waveform"), size: logoSize)
                } accessory: {
                    if row.isDefault { DefaultBadge() }
                    if row.isRecommended { Text("Recommended").font(.caption).foregroundStyle(.secondary) }
                    if let fraction = current.fraction {
                        ProgressView(value: fraction)
                            .progressViewStyle(.circular)
                            .accessibilityLabel("Downloading \(model.title)")
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!row.canSelect)
            accessory(row, state: current)
        }
        .swipeActions(edge: .trailing) {
            if row.canDelete { Button("Delete", role: .destructive) { confirmsDelete = true } }
        }
        .contextMenu {
            if row.canSelect { Button("Use as default", systemImage: "checkmark.circle") { hub.select(model) } }
            if row.canDelete { Button("Delete", systemImage: "trash", role: .destructive) { confirmsDelete = true } }
        }
        .confirmationDialog("Delete \(model.title)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { remove() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice.row.\(model.id)")
    }

    private func secondary(_ row: VoiceModelsRules.Row, failed: Bool) -> Text {
        guard let note = row.note else { return Text(row.detail) }
        return Text(row.detail) + Text("\n") + Text(note).foregroundStyle(failed ? Color.red : Color.secondary)
    }

    @ViewBuilder
    private func accessory(_ row: VoiceModelsRules.Row, state: ModelDownloadState) -> some View {
        switch state {
        case .notInstalled, .failed:
            if row.canGet {
                Button { hub.downloader.start(model) } label: { Text(state.isFailed ? "Retry" : "Get").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Get \(model.title)")
            }
        case .installed:
            Image(systemName: row.isDefault ? "checkmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel(row.isDefault ? "Default" : "Installed")
        case .downloading, .paused, .verifying:
            Button(role: .cancel) { hub.downloader.cancel(model) } label: { Text("Cancel").frame(minWidth: 44, minHeight: 44) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }

    private func remove() {
        if hub.isSelected(model) { hub.select(.system(model.kind)) }
        try? hub.downloader.delete(model)
        hub.forget(model)
    }
}
