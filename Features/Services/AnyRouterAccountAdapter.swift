import Foundation
import Observation

/// Bridges lane B's `AnyRouterAuth` to the UI's `AccountService`.
@MainActor @Observable
final class AnyRouterAccountAdapter: AccountService {
    private let auth: AnyRouterAuth
    private let loader: AccountSummaryLoader
    private(set) var summary: AccountSummary?

    struct SignInFailed: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    init(auth: AnyRouterAuth, loader: AccountSummaryLoader = AccountSummaryLoader()) {
        self.auth = auth
        self.loader = loader
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
        summary = nil
    }

    func refreshSummary() async {
        guard let token = auth.store.token() else {
            summary = nil
            return
        }
        // A failed reload keeps the last good summary.
        if let loaded = await loader.load(token: token) { summary = loaded }
    }
}
