import SwiftUI

/// Whether the voice button first offers a speech model to download, and what its button says.
enum VoiceModeGateLogic {
    /// The recommended speech model, or nil to dictate at once: nothing fits this device, a downloaded speech model is
    /// already installed, or the person chose Not Now before.
    static func offer(recommended: VoiceModel?, installedSTT: Bool, declined: Bool) -> VoiceModel? {
        guard !installedSTT, !declined else { return nil }
        return recommended
    }

    /// The model's real download size, from the catalog.
    static func sizeLabel(_ model: VoiceModel) -> String {
        ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
    }

    static func downloadTitle(_ model: VoiceModel) -> String {
        "Download (\(sizeLabel(model)))"
    }

    /// The model named plainly: "Whisper Base · 99 languages · 150 MB".
    static func headline(_ model: VoiceModel) -> String {
        [model.title, model.languageSummary, sizeLabel(model)].joined(separator: " · ")
    }

    /// The speech models to pick from: the downloads of Settings › Local Models › Voice (`models` is that list, System row
    /// included) that can run on this device, in the same order.
    static func options(_ models: [VoiceModel], memory: DeviceMemory) -> [VoiceModel] {
        models.filter { !$0.isSystem && $0.kind == .stt && VoiceFit.verdict($0, memory: memory) != .wontFit }
    }

    /// One entry of the picker: the headline plus "Recommended" for this device's pick, or the fit note when it is tight.
    static func optionTitle(_ model: VoiceModel, recommended: VoiceModel?, memory: DeviceMemory) -> String {
        var parts = [headline(model)]
        if model.id == recommended?.id {
            parts.append("Recommended")
        } else if VoiceFit.verdict(model, memory: memory) == .tight {
            parts.append(VoiceFit.Verdict.tight.title)
        }
        return parts.joined(separator: " · ")
    }
}

/// Voice Mode before its model is on the phone: which model it is, the real size and a way to pick another one, then the
/// download's progress. `model` is the offer (the device's recommendation); the person can change it. When the chosen model
/// is installed, `onReady` runs and the caller closes this and starts listening.
struct VoiceModeGate: View {
    @Environment(AppState.self) private var app
    let model: VoiceModel
    let downloader: VoiceModelDownloader
    var onReady: () -> Void
    var onNotNow: () -> Void
    @State private var picked: VoiceModel?

    private var chosen: VoiceModel { picked ?? model }
    private var state: ModelDownloadState { downloader.state(for: chosen) }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform")
                .font(.largeTitle)
                .imageScale(.large)
                .symbolEffect(.variableColor.iterative, isActive: state.isActive)
                .accessibilityHidden(true)
            Text("Voice Mode")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("voice-gate.title")
            Text(VoiceModeGateLogic.headline(chosen))
                .font(.headline)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("voice-gate.model")
            if let summary = chosen.summary {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("voice-gate.summary")
            }
            Spacer()
            actions
        }
        .padding(.vertical, 24)
        .readableWidth()
        .onChange(of: state) { _, new in
            guard new == .installed else { return }
            onReady()
            // The caller's onReady selects the offer; the model that finished is the one the person chose, and it is the
            // setting Settings › Local Models › Voice reads too.
            app.voice.select(chosen)
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            switch state {
            case .downloading, .paused, .verifying:
                ProgressView(value: state.fraction ?? 0)
                    .accessibilityLabel("Downloading the voice model")
                    .accessibilityIdentifier("voice-gate.progress")
                Button("Cancel", role: .cancel) { downloader.cancel(chosen) }
                    .controlSize(.large)
                    .frame(minHeight: 44)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                wideButton("Try Again", id: "voice-gate.download") { downloader.start(chosen) }
                chooser
                notNow
            default:
                wideButton(VoiceModeGateLogic.downloadTitle(chosen), id: "voice-gate.download") { downloader.start(chosen) }
                chooser
                notNow
            }
        }
    }

    /// "Choose another model": the downloadable speech models that fit this phone, the same catalog and fit as Settings.
    @ViewBuilder
    private var chooser: some View {
        let memory = DeviceMemory.current()
        let options = VoiceModeGateLogic.options(app.voice.models(.stt), memory: memory)
        let recommended = app.voice.recommended(.stt, memory: memory)
        if options.count > 1 {
            Menu("Choose another model") {
                Picker("Voice model", selection: Binding(
                    get: { chosen.id },
                    set: { id in picked = options.first { $0.id == id } }
                )) {
                    ForEach(options) { option in
                        Text(VoiceModeGateLogic.optionTitle(option, recommended: recommended, memory: memory)).tag(option.id)
                    }
                }
                .pickerStyle(.inline)
            }
            .controlSize(.large)
            .frame(minHeight: 44)
            .accessibilityIdentifier("voice-gate.choose")
        }
    }

    private var notNow: some View {
        Button("Not Now", action: onNotNow)
            .controlSize(.large)
            .frame(minHeight: 44)
            .accessibilityIdentifier("voice-gate.not-now")
    }

    private func wideButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity).prominentLabel() }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .accessibilityIdentifier(id)
    }
}
