import Foundation
import Observation

/// Bridges lane B's `AnyRouterAuth` to the UI's `AccountService`.
@MainActor @Observable
final class AnyRouterAccountAdapter: AccountService {
    private let auth: AnyRouterAuth
    private let loader: AccountSummaryLoader
    private let telemetry: any Telemetry
    /// Where the last summary waits for the next launch. Never the token.
    @ObservationIgnored private let cache: UserDefaults?
    private(set) var summary: AccountSummary?

    static let summaryCacheKey = "account.summaryCache"

    struct SignInFailed: LocalizedError {
        let message: String
        /// The server was briefly unavailable; the same request is worth another try.
        var isBusy = false
        var errorDescription: String? { message }
    }

    init(auth: AnyRouterAuth, loader: AccountSummaryLoader = AccountSummaryLoader(),
         telemetry: any Telemetry = NoopTelemetry(), cache: UserDefaults? = nil) {
        self.auth = auth
        self.loader = loader
        self.telemetry = telemetry
        self.cache = cache
        // Stale while revalidating: a signed-in person sees the last summary at once, `refreshSummary` replaces it.
        if auth.isSignedIn, let data = cache?.data(forKey: Self.summaryCacheKey) {
            summary = try? JSONDecoder().decode(AccountSummary.self, from: data)
        }
    }

    var state: AccountState {
        switch auth.state {
        case .signedOut: .signedOut
        case .signingIn: .signingIn
        case .signedIn: .signedIn(label: nil)
        }
    }

    func signIn(mode: AuthMode) async throws {
        await auth.signIn(mode: mode)
        if let message = auth.lastError {
            telemetry.track(.signInFail(reason: auth.lastFailureWasBusy ? "busy" : "error"))
            throw SignInFailed(message: message, isBusy: auth.lastFailureWasBusy)
        }
        // No error and no key: the user closed the sign-in sheet.
        if case .signedIn = auth.state { telemetry.track(.signInOK) } else { telemetry.track(.signInFail(reason: "cancelled")) }
    }

    func signOut() async {
        auth.signOut()
        forgetSummary()
    }

    /// Signed out by any path: the menu, a 401, or a key the Keychain no longer has.
    func forgetSummary() {
        summary = nil
        cache?.removeObject(forKey: Self.summaryCacheKey)
    }

    func refreshSummary() async {
        let store = auth.store
        // Off the main thread: a Keychain read can block for seconds on a cold boot.
        let stored = await Task.detached(priority: .userInitiated) { store.token() }.value
        guard let token = stored else {
            forgetSummary()
            return
        }
        // A failed reload keeps the last good summary.
        guard let loaded = await loader.load(token: token) else { return }
        summary = loaded
        cache?.set(try? JSONEncoder().encode(loaded), forKey: Self.summaryCacheKey)
    }
}
