import Foundation

/// Where one step of a reply's trace stands: a tool call, a subagent, reasoning. `TraceRow` draws it.
enum TraceStatus: Equatable, Sendable {
    case running
    /// The call waits for the person to allow or deny it.
    case awaitingApproval
    case done
    case failed
    /// The person did not allow the call.
    case denied
    /// Stopped by the person before it ended.
    case cancelled

    /// What VoiceOver reads after the row's title.
    var accessibilityText: String {
        switch self {
        case .running: String(localized: "Running")
        case .awaitingApproval: String(localized: "Waiting for your approval")
        case .done: String(localized: "Done")
        case .failed: String(localized: "Failed")
        case .denied: String(localized: "Not allowed")
        case .cancelled: String(localized: "Cancelled")
        }
    }

    /// Failed and denied steps stay on screen after the chain folds into one sentence.
    var staysVisible: Bool { self == .failed || self == .denied }
}
