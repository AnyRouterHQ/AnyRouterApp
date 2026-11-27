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
    static func downloadTitle(_ model: VoiceModel) -> String {
        "Download (\(ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)))"
    }
}

/// Voice Mode before its model is on the phone: what it needs and the real size, then the download's progress. When the
/// model is installed, `onReady` runs and the caller closes this and starts listening.
struct VoiceModeGate: View {
    let model: VoiceModel
    let downloader: VoiceModelDownloader
    var onReady: () -> Void
    var onNotNow: () -> Void

    private var state: ModelDownloadState { downloader.state(for: model) }

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
            Text("Download the voice model to use Voice Mode.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            actions
        }
        .padding(.vertical, 24)
        .readableWidth()
        .onChange(of: state) { _, new in
            if new == .installed { onReady() }
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
                Button("Cancel", role: .cancel) { downloader.cancel(model) }
                    .controlSize(.large)
                    .frame(minHeight: 44)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                wideButton("Try Again", id: "voice-gate.download") { downloader.start(model) }
                notNow
            default:
                wideButton(VoiceModeGateLogic.downloadTitle(model), id: "voice-gate.download") { downloader.start(model) }
                notNow
            }
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
