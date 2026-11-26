import Foundation

enum OnboardingLogic {
    enum Choice: Hashable, Sendable { case apple, local, cloud }

    /// Largest local model we offer first: at most this big, so a first download stays quick.
    static let recommendedMaxBytes: Int64 = 1_500_000_000

    /// First catalog entry flagged for onboarding that fits the device; else the first small one that fits;
    /// else the smallest one that fits at all.
    static func recommendedLocal(in catalog: [LocalModelEntry]) -> LocalModelEntry? {
        let usable = catalog.filter { $0.fit != .wontFit && $0.unavailableReason == nil }
        if let flagged = usable.first(where: \.isOnboarding) { return flagged }
        if let small = usable.first(where: { ($0.descriptor.sizeBytes ?? .max) <= recommendedMaxBytes }) { return small }
        return usable.min { ($0.descriptor.sizeBytes ?? .max) < ($1.descriptor.sizeBytes ?? .max) }
    }

    /// Whether the person can leave onboarding with this choice working right now.
    static func canFinish(choice: Choice?, appleAvailable: Bool, localState: DownloadState, signedIn: Bool) -> Bool {
        switch choice {
        case .apple: appleAvailable
        case .local: localState == .installed
        case .cloud: signedIn
        case nil: false
        }
    }

    /// Where "Use on-device only" goes: straight to chat when Apple Intelligence is there, else to the local model step.
    enum OnDeviceRoute: Equatable { case chat(Choice), pickLocal }

    static func onDeviceRoute(appleAvailable: Bool) -> OnDeviceRoute {
        appleAvailable ? .chat(.apple) : .pickLocal
    }

    /// The model to select on finish, by id.
    static func modelID(for choice: Choice, models: [ModelDescriptor], local: LocalModelEntry?) -> String? {
        switch choice {
        case .apple: models.first { $0.source == .apple && $0.isInstalled }?.id
        case .local: local?.id
        case .cloud: models.first { $0.source == .anyrouter }?.id
        }
    }
}

/// The browser sign-in as one small machine, so the screen never holds a flag pair that disagrees.
///
///     signedOut --start(mode)--> authorizing(mode) --succeeded--> signedIn(verified | unverified)
///                                      |  \-- cancelled --> signedOut
///                                      \----- failed -----> failed(reason, retry: mode) --start--> authorizing
///
/// An unverified email is a state of being signed in, not a failure: chat works and Settings asks later.
enum SignInFlow {
    enum EmailStatus: Equatable, Sendable { case verified, unverified }

    enum FailureReason: Equatable, Sendable {
        /// The server answered 5xx. Same request, try again.
        case busy
        case message(String)

        var text: String {
            switch self {
            case .busy: "AnyRouter is busy. Try again in a moment."
            case .message(let text): text
            }
        }
    }

    enum State: Equatable, Sendable {
        case signedOut
        case authorizing(AuthMode)
        case signedIn(EmailStatus)
        case failed(FailureReason, retry: AuthMode)
    }

    enum Event: Equatable, Sendable {
        case start(AuthMode)
        /// The browser handed back a key. `emailVerified` is /me's answer; nil (not said) counts as verified.
        case succeeded(emailVerified: Bool?)
        /// The person closed the sign-in sheet. Not an error.
        case cancelled
        case failed(FailureReason)
        /// Signed out, or the key was refused.
        case signedOut
    }

    static func reduce(_ state: State, _ event: Event) -> State {
        switch (state, event) {
        case (_, .signedOut):
            return .signedOut
        case (.signedOut, .start(let mode)), (.failed, .start(let mode)):
            return .authorizing(mode)
        case (.authorizing, .succeeded(let verified)):
            return .signedIn(verified == false ? .unverified : .verified)
        case (.authorizing, .cancelled):
            return .signedOut
        case (.authorizing(let mode), .failed(let reason)):
            return .failed(reason, retry: mode)
        default:
            // A second tap while the sheet is open, or a late answer after the flow ended.
            return state
        }
    }
}
