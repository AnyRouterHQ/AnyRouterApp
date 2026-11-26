import Foundation

/// What the round button at the end of the composer field does right now.
enum ComposerAction: Equatable {
    case voice, send, stop

    /// A reply in progress always shows stop. Text or an attachment shows send, even while it cannot be sent yet
    /// (a model is loading), so the button does not flip while the reader types. Otherwise it offers voice input.
    static func current(isStreaming: Bool, hasInput: Bool, hasAttachments: Bool) -> ComposerAction {
        if isStreaming { return .stop }
        return hasInput || hasAttachments ? .send : .voice
    }

    var title: String {
        switch self {
        case .voice: "Voice input"
        case .send: "Send"
        case .stop: "Stop"
        }
    }

    var symbol: String {
        switch self {
        case .voice: "waveform"
        case .send: "arrow.up"
        case .stop: "stop.fill"
        }
    }
}
