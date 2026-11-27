import Foundation

/// What the round button at the end of the composer field does right now.
enum ComposerAction: Equatable {
    case voice, send, stop
    /// A reply is streaming and a message is typed: it waits in the queue. Stop has its own button beside this one.
    case queue
    /// Dictation is running: the same button ends it and keeps the words.
    case stopDictation

    /// A reply in progress shows stop, or the queue button when something is typed. Text or an attachment shows send, even while it cannot be sent yet
    /// (a model is loading), so the button does not flip while the reader types. Otherwise it offers voice input.
    static func current(isStreaming: Bool, hasInput: Bool, hasAttachments: Bool, isDictating: Bool = false) -> ComposerAction {
        if isStreaming { return hasInput || hasAttachments ? .queue : .stop }
        if isDictating { return .stopDictation }
        return hasInput || hasAttachments ? .send : .voice
    }

    var title: String {
        switch self {
        case .voice: "Voice input"
        case .send: "Send"
        case .queue: "Add to queue"
        case .stop: "Stop"
        case .stopDictation: "Stop dictation"
        }
    }

    var symbol: String {
        switch self {
        case .voice: "waveform"
        case .send: "arrow.up"
        case .queue: "text.badge.plus"
        case .stop: "stop.fill"
        case .stopDictation: "mic.fill"
        }
    }
}
