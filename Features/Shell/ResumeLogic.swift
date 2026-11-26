import Foundation

/// How long the app may stay in the background before it opens on a new chat instead of the last conversation.
enum NewChatDelay: String, CaseIterable, Identifiable, Sendable {
    case immediately, oneMinute, fiveMinutes, fifteenMinutes, oneHour, never

    var id: String { rawValue }

    static let standard = NewChatDelay.oneMinute

    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .never: "Never"
        }
    }

    /// Nil for `never`.
    var seconds: TimeInterval? {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        case .oneHour: 3600
        case .never: nil
        }
    }
}

enum ResumeDecision: Equatable, Sendable {
    /// Keep showing the conversation that was open.
    case resume
    /// Open an empty chat (the home screen with its presets). No thread is stored until the first send.
    case fresh
}

enum ResumeLogic {
    /// What to show when the app becomes active again. A new chat starts once the app has been away for the whole
    /// delay (exactly 60 seconds counts for "1 minute"); a reply that is still streaming always stays on screen;
    /// no recorded time (first launch) or a clock that went backwards keeps the conversation.
    static func decide(backgroundedAt: Date?, now: Date, delay: NewChatDelay, isStreaming: Bool) -> ResumeDecision {
        guard !isStreaming, let backgroundedAt, let limit = delay.seconds else { return .resume }
        let away = now.timeIntervalSince(backgroundedAt)
        return away >= 0 && away >= limit ? .fresh : .resume
    }
}
