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
    func signIn() async throws
    func signOut() async
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

    func signIn() async throws { throw Unavailable() }
    func signOut() async {}
}
