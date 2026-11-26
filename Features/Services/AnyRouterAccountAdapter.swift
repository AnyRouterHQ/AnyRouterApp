import Foundation
import Observation

/// Bridges lane B's `AnyRouterAuth` to the UI's `AccountService`.
@MainActor @Observable
final class AnyRouterAccountAdapter: AccountService {
    private let auth: AnyRouterAuth
    private let loader: AccountSummaryLoader
    private let telemetry: any Telemetry
    private(set) var summary: AccountSummary?

    struct SignInFailed: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    init(auth: AnyRouterAuth, loader: AccountSummaryLoader = AccountSummaryLoader(),
         telemetry: any Telemetry = NoopTelemetry()) {
        self.auth = auth
        self.loader = loader
        self.telemetry = telemetry
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
        if let message = auth.lastError {
            telemetry.track(.signInFail(reason: "error"))
            throw SignInFailed(message: message)
        }
        // No error and no key: the user closed the sign-in sheet.
        if case .signedIn = auth.state { telemetry.track(.signInOK) } else { telemetry.track(.signInFail(reason: "cancelled")) }
    }

    func signOut() async {
        auth.signOut()
        summary = nil
    }

    func refreshSummary() async {
        let store = auth.store
        // Off the main thread: a Keychain read can block for seconds on a cold boot.
        let stored = await Task.detached(priority: .userInitiated) { store.token() }.value
        guard let token = stored else {
            summary = nil
            return
        }
        // A failed reload keeps the last good summary.
        if let loaded = await loader.load(token: token) { summary = loaded }
    }
}
