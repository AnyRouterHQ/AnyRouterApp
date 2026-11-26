import Foundation
import Observation

/// Bridges lane B's `AnyRouterAuth` to the UI's `AccountService`.
@MainActor @Observable
final class AnyRouterAccountAdapter: AccountService {
    private let auth: AnyRouterAuth

    struct SignInFailed: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    init(auth: AnyRouterAuth) {
        self.auth = auth
    }

    var state: AccountState {
        switch auth.state {
        case .signedOut: .signedOut
        case .signingIn: .signingIn
        case .signedIn: .signedIn(label: nil)
        }
    }

    func signIn() async throws {
        await auth.signIn()
        if let message = auth.lastError { throw SignInFailed(message: message) }
    }

    func signOut() async {
        auth.signOut()
    }
}
