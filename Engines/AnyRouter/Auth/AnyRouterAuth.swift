import Foundation
import Observation

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
    private let client: OAuthClient

    init(store: KeychainStore = KeychainStore(), client: OAuthClient? = nil) {
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
        state = store.token() != nil ? .signedIn(expiresAt: store.expiresAt()) : .signedOut
    }

    func signIn() async {
        guard state != .signingIn else { return }
        state = .signingIn
        lastError = nil
        do {
            let issued = try await client.signIn()
            store.save(token: issued.accessToken, expiresAt: issued.expiresAt)
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
    func makeEngine(config: AnyRouterConfig = .standard) -> AnyRouterEngine {
        AnyRouterEngine(tokens: store, config: config) { [weak self] in
            await MainActor.run { self?.handleUnauthorized() }
        }
    }
}
