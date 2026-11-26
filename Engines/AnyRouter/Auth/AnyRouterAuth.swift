import Foundation
import Observation

/// The browser sign-in step. `OAuthClient` is the real one; tests script it.
@MainActor
protocol OAuthSigning {
    func signIn() async throws -> IssuedToken
}

/// Sign-in state the UI observes. Owns the Keychain store and the OAuth flow.
@MainActor
@Observable
final class AnyRouterAuth {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(expiresAt: Date?)
    }

    private(set) var state: State = .signedOut
    private(set) var lastError: String?

    let store: KeychainStore
    private let client: any OAuthSigning
    /// Called when the user becomes signed in or signed out (also on a 401 or an expired key).
    @ObservationIgnored var onSignedInChange: (@MainActor (Bool) -> Void)?

    init(store: KeychainStore = KeychainStore(), client: (any OAuthSigning)? = nil) {
        self.store = store
        self.client = client ?? OAuthClient()
        refresh()
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    /// Re-reads the Keychain: a stored token past its expiry counts as signed out.
    func refresh() {
        let was = isSignedIn
        state = store.token() != nil ? .signedIn(expiresAt: store.expiresAt()) : .signedOut
        if was != isSignedIn { onSignedInChange?(isSignedIn) }
    }

    func signIn() async {
        guard state != .signingIn else { return }
        state = .signingIn
        lastError = nil
        do {
            let issued = try await client.signIn()
            if !store.save(token: issued.accessToken, expiresAt: issued.expiresAt) {
                lastError = "Could not save the sign-in to the Keychain."
            }
        } catch {
            if case OAuthClient.Failure.cancelled = error {
                lastError = nil
            } else {
                lastError = error.localizedDescription
            }
        }
        refresh()
    }

    func signOut() {
        store.clear()
        lastError = nil
        refresh()
    }

    /// Engine saw a 401: the key expired or was revoked.
    func handleUnauthorized() {
        store.clear()
        refresh()
    }

    /// Engine wired to this auth state.
    func makeEngine(config: AnyRouterConfig = .standard, session: URLSession = .shared) -> AnyRouterEngine {
        AnyRouterEngine(tokens: store, config: config, session: session) { [weak self] in
            await MainActor.run { self?.handleUnauthorized() }
        }
    }
}
