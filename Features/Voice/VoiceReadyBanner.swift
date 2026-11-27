import SwiftUI

/// "Voice Mode is ready" over the top of the app when the download finished while the app was in front (or the person came
/// back to it). A custom floating control, so it carries its own glass: no system banner can sit inside the app's window.
/// Start asks the composer to listen (`VoiceHub.startRequests`). It goes away on its own after a few seconds in front.
struct VoiceReadyBanner: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    private var isReady: Bool { app.voice.voiceDownload.phase == .ready }

    var body: some View {
        ZStack {
            if isReady {
                HStack(spacing: 8) {
                    Label(VoiceReadyLogic.title, systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Start") { app.voice.requestStart() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("voice-ready.start")
                    Button(role: .close) { app.voice.dismissReady() }
                        .accessibilityIdentifier("voice-ready.close")
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("voice-ready.banner")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.default, value: isReady)
        .sensoryFeedback(.success, trigger: isReady) { _, ready in ready }
        .task(id: isReady && scenePhase == .active) {
            guard isReady, scenePhase == .active else { return }
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { app.voice.dismissReady() }
        }
        // Listening has started (this banner's Start, or the voice button): it has done its job.
        .onChange(of: app.dictation.isActive) { _, active in
            if active { app.voice.dismissReady() }
        }
    }
}
