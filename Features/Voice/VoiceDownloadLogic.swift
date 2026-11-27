import Foundation

/// What the voice button and the banner show about the Voice Mode download. No views here.
struct VoiceDownloadState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case downloading
        case verifying
        case paused
        case failed
        /// Just finished: the model is installed and selected.
        case ready
    }

    var phase: Phase = .idle
    var modelID: String?
    var title: String?
    /// 0...1 while the size is known, nil for an indeterminate ring.
    var fraction: Double?
    var message: String?

    static let idle = VoiceDownloadState()

    /// A ring belongs on the button.
    var showsProgress: Bool {
        switch phase {
        case .downloading, .verifying, .paused: true
        default: false
        }
    }

    /// The person can start it again.
    var canRetry: Bool { phase == .paused || phase == .failed }
}

enum VoiceDownloadLogic {
    /// The state of the model Voice Mode waits for: the `target` (chosen on the gate, not installed yet), else the one that
    /// `finished` last. `download` is that model's state in the downloader.
    static func state(
        target: String?, finished: String?, models: [VoiceModel], download: (VoiceModel) -> ModelDownloadState
    ) -> VoiceDownloadState {
        guard let id = target ?? finished, let model = models.first(where: { $0.id == id }) else { return .idle }
        var state = VoiceDownloadState(modelID: model.id, title: model.title)
        switch download(model) {
        case .notInstalled:
            return .idle
        case .downloading:
            state.phase = .downloading
        case .paused:
            state.phase = .paused
        case .verifying:
            state.phase = .verifying
        case .installed:
            return target == nil ? VoiceDownloadState(phase: .ready, modelID: model.id, title: model.title) : .idle
        case .failed(let message):
            state.phase = .failed
            state.message = message
            return state
        }
        state.fraction = download(model).fraction
        return state
    }
}
