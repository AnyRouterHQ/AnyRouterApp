import Foundation

/// Why a reply did not finish. Stored on the reply (`MessageRecord.failure`), so a failed reply reads the same after a relaunch.
struct ReplyFailure: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case offline, timeout, signedOut, outOfCredits, rateLimited, modelUnavailable, contextTooLong
        case toolFailed, localOutOfMemory, localLoadFailed, cancelled, unknown
        /// Set when a reply starts and cleared when it ends: still there after a launch, the app closed while it was written.
        case interrupted

        /// A kind this build does not know (saved by a newer one) reads as unknown instead of failing the whole reply.
        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    /// What the reply offers to do about it.
    enum Action: Hashable, Sendable {
        case retry, signIn, chooseModel, shortenChat, openSettings
        /// A reply from a model on this device asks a cloud model instead, after a notice (agent design X1).
        case askCloudModel
    }

    var kind: Kind
    /// The engine's own words, shown behind Details.
    var detail: String
}

/// Engine errors in, one plain sentence and one action out. The raw text is kept as the detail.
enum ReplyFailureLogic {
    static func classify(_ error: any Error) -> ReplyFailure {
        ReplyFailure(kind: kind(of: error), detail: error.localizedDescription)
    }

    static func kind(of error: any Error) -> ReplyFailure.Kind {
        switch error {
        case is CancellationError: return .cancelled
        case let error as URLError: return kind(of: error.code)
        case let error as AnyRouterError: return kind(of: error)
        case let error as GGUFError: return kind(of: error)
        case let error as MLXError: return kind(of: error)
        case let error as AppleFoundationEngine.Failure: return kind(of: error)
        case is MCPError: return .toolFailed
        default: return kind(ofText: error.localizedDescription)
        }
    }

    /// One short sentence for the reply.
    static func message(for kind: ReplyFailure.Kind) -> String {
        switch kind {
        case .offline: String(localized: "You're offline. Connect to the internet, then try again.")
        case .timeout: String(localized: "The model took too long to answer.")
        case .signedOut: String(localized: "Your AnyRouter sign-in has ended. Sign in again to keep chatting.")
        case .outOfCredits: String(localized: "Your AnyRouter credits have run out. Choose a free or on-device model, or add credits.")
        case .rateLimited: String(localized: "The model is busy right now. Wait a moment, then try again.")
        case .modelUnavailable: String(localized: "This model can't answer right now.")
        case .contextTooLong: String(localized: "This chat is too long for the model. Shorten it, then try again.")
        case .toolFailed: String(localized: "A tool the model used stopped working.")
        case .localOutOfMemory: String(localized: "The model needs more memory than this device has free.")
        case .localLoadFailed: String(localized: "The model on this device couldn't load.")
        case .cancelled: String(localized: "The reply stopped before it finished.")
        case .unknown: String(localized: "Something went wrong with this reply.")
        case .interrupted: String(localized: "The reply stopped when the app closed.")
        }
    }

    static func symbol(for kind: ReplyFailure.Kind) -> String {
        switch kind {
        case .offline: "wifi.slash"
        case .timeout: "clock.badge.exclamationmark"
        case .signedOut: "person.crop.circle.badge.exclamationmark"
        case .outOfCredits: "creditcard"
        case .rateLimited: "hourglass"
        case .modelUnavailable: "exclamationmark.bubble"
        case .contextTooLong: "text.badge.xmark"
        case .toolFailed: "wrench.and.screwdriver"
        case .localOutOfMemory: "memorychip"
        case .localLoadFailed: "iphone.slash"
        case .cancelled: "stop.circle"
        case .unknown: "exclamationmark.triangle"
        case .interrupted: "arrow.clockwise.circle"
        }
    }

    /// The action that fixes it, then Retry when that is something else and the reply can still be retried. A device
    /// model that could not answer (too long a chat, too little memory, not loaded) can hand the question to a cloud
    /// model when `canAskCloud`; the app never does that by itself.
    static func actions(for kind: ReplyFailure.Kind, canRetry: Bool, canAskCloud: Bool = false) -> [ReplyFailure.Action] {
        let escalates = canAskCloud && [.contextTooLong, .localOutOfMemory, .localLoadFailed, .modelUnavailable].contains(kind)
        return fixes(for: kind, canRetry: canRetry) + (escalates ? [.askCloudModel] : [])
    }

    /// What the reply shows: one primary button and the other actions behind More. A device model that cannot load or
    /// fit in memory is best answered by a cloud model, so that leads when it is offered; otherwise the fix leads.
    struct ActionPlan: Equatable, Sendable {
        var primary: ReplyFailure.Action?
        var more: [ReplyFailure.Action]
    }

    static func plan(for kind: ReplyFailure.Kind, canRetry: Bool, canAskCloud: Bool = false) -> ActionPlan {
        let all = actions(for: kind, canRetry: canRetry, canAskCloud: canAskCloud)
        let primary = [.localLoadFailed, .localOutOfMemory].contains(kind) && all.contains(.askCloudModel) ? .askCloudModel : all.first
        return ActionPlan(primary: primary, more: all.filter { $0 != primary })
    }

    private static func fixes(for kind: ReplyFailure.Kind, canRetry: Bool) -> [ReplyFailure.Action] {
        let primary: ReplyFailure.Action = switch kind {
        case .signedOut: .signIn
        case .outOfCredits, .modelUnavailable, .localOutOfMemory: .chooseModel
        case .contextTooLong: .shortenChat
        case .localLoadFailed: .openSettings
        case .offline, .timeout, .rateLimited, .toolFailed, .cancelled, .unknown, .interrupted: .retry
        }
        guard canRetry else { return primary == .retry ? [] : [primary] }
        return primary == .retry ? [.retry] : [primary, .retry]
    }

    static func title(of action: ReplyFailure.Action) -> String {
        switch action {
        case .retry: String(localized: "Retry")
        case .signIn: String(localized: "Sign in")
        case .chooseModel: String(localized: "Choose another model")
        case .shortenChat: String(localized: "Shorten chat")
        case .openSettings: String(localized: "Open Local Models")
        case .askCloudModel: String(localized: "Ask a cloud model")
        }
    }

    // MARK: - Private

    private static func kind(of code: URLError.Code) -> ReplyFailure.Kind {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            .offline
        case .timedOut: .timeout
        case .cancelled: .cancelled
        case .userAuthenticationRequired: .signedOut
        default: .unknown
        }
    }

    private static func kind(of error: AnyRouterError) -> ReplyFailure.Kind {
        switch error {
        case .signedOut: return .signedOut
        case .badResponse: return .unknown
        case .stream(let message): return kind(ofText: message)
        case .http(let status, let message):
            switch status {
            case 401: return .signedOut
            case 402: return .outOfCredits
            case 404: return .modelUnavailable
            case 408, 504: return .timeout
            case 413: return .contextTooLong
            case 429: return .rateLimited
            case 500..<600: return .modelUnavailable
            default: return kind(ofText: message)
            }
        }
    }

    private static func kind(of error: GGUFError) -> ReplyFailure.Kind {
        switch error {
        case .imagesWontFit, .contextFailed: .localOutOfMemory
        case .loadFailed, .modelNotInstalled, .projectorLoadFailed: .localLoadFailed
        case .promptTooLong: .contextTooLong
        case .imagesNotSupported: .modelUnavailable
        case .tokenizeFailed, .decodeFailed, .imageUnreadable, .imageEncodeFailed: .unknown
        }
    }

    private static func kind(of error: MLXError) -> ReplyFailure.Kind {
        switch error {
        case .unavailable, .modelNotInstalled: .localLoadFailed
        case .emptyConversation: .unknown
        }
    }

    private static func kind(of error: AppleFoundationEngine.Failure) -> ReplyFailure.Kind {
        switch error {
        case .unavailable: .modelUnavailable
        case .emptyPrompt: .unknown
        }
    }

    /// Servers and on-device runtimes often say what went wrong only in words.
    static func kind(ofText text: String) -> ReplyFailure.Kind {
        let text = text.lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        if has("context length", "context window", "context size", "maximum context", "too many tokens", "prompt is too long") { return .contextTooLong }
        if has("rate limit", "too many requests") { return .rateLimited }
        if has("credit", "insufficient balance", "payment required") { return .outOfCredits }
        if has("timed out", "timeout") { return .timeout }
        return .unknown
    }
}
