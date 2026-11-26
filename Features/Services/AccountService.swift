import Foundation
import Observation

enum AccountState: Equatable, Sendable {
    case signedOut
    case signingIn
    case signedIn(label: String?)
}

/// What the UI needs from AnyRouter sign-in. Lane B conforms (`@MainActor @Observable` class).
@MainActor
protocol AccountService: AnyObject {
    var state: AccountState { get }
    /// Profile and spend for the account card. Nil until loaded, or when signed out.
    var summary: AccountSummary? { get }
    /// Opens the browser sign-in (`.signIn`) or sign-up (`.signUp`). Both end signed in. Returns on cancel without an error.
    func signIn(mode: AuthMode) async throws
    func signOut() async
    /// Reloads `summary`. Does nothing when signed out.
    func refreshSummary() async
}

extension AccountService {
    func signIn() async throws { try await signIn(mode: .signIn) }
}

extension AccountState {
    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

/// Default until an engine lane provides the real service.
@MainActor @Observable
final class UnavailableAccountService: AccountService {
    private(set) var state: AccountState = .signedOut

    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Sign-in is not available in this build." }
    }

    func signIn(mode: AuthMode) async throws { throw Unavailable() }
    func signOut() async {}
    var summary: AccountSummary? { nil }
    func refreshSummary() async {}
}
