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

    /// How the first state is found. A Keychain read can block for seconds on a cold boot, so launch uses `deferred`.
    enum Restore {
        /// Read the Keychain now, on the calling thread.
        case immediate
        /// Show the last known state from `hints` at once, then confirm with the Keychain off the main thread.
        case deferred
    }

    static let signedInHintKey = "auth.signedInHint"
    static let expiryHintKey = "auth.expiresAtHint"

    let store: any AuthTokenStore
    private let client: any OAuthSigning
    /// Where the last known state is kept for the next launch. Not a secret: a flag and an expiry time.
    @ObservationIgnored private let hints: UserDefaults?
    /// Bumps on every applied state, so a Keychain answer that arrives late can tell it is stale.
    @ObservationIgnored private var stateVersion = 0
    /// Called when the user becomes signed in or signed out (also on a 401 or an expired key).
    @ObservationIgnored var onSignedInChange: (@MainActor (Bool) -> Void)?

    init(
        store: any AuthTokenStore = KeychainStore(), client: (any OAuthSigning)? = nil,
        restore: Restore = .immediate, hints: UserDefaults? = nil
    ) {
        self.store = store
        self.client = client ?? OAuthClient()
        self.hints = hints
        switch restore {
        case .immediate:
            refresh()
        case .deferred:
            applyHint()
            let version = stateVersion
            Task { await confirmStoredSignIn(since: version) }
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    /// Re-reads the Keychain: a stored token past its expiry counts as signed out.
    func refresh() {
        let signedIn = store.token() != nil
        apply(signedIn: signedIn, expiresAt: signedIn ? store.expiresAt() : nil)
    }

    private func apply(signedIn: Bool, expiresAt: Date?) {
        let was = isSignedIn
        state = signedIn ? .signedIn(expiresAt: expiresAt) : .signedOut
        stateVersion += 1
        remember(expiresAt: expiresAt)
        if was != isSignedIn { onSignedInChange?(isSignedIn) }
    }

    private func remember(expiresAt: Date?) {
        guard let hints else { return }
        hints.set(isSignedIn, forKey: Self.signedInHintKey)
        hints.set(isSignedIn ? expiresAt?.timeIntervalSince1970 : nil, forKey: Self.expiryHintKey)
    }

    /// The state the last run ended in. A key past its remembered expiry counts as signed out.
    private func applyHint() {
        guard let hints, hints.bool(forKey: Self.signedInHintKey) else { return }
        let expiry = (hints.object(forKey: Self.expiryHintKey) as? Double).map { Date(timeIntervalSince1970: $0) }
        if let expiry, expiry <= Date() { return }
        state = .signedIn(expiresAt: expiry)
    }

    /// The Keychain read behind a deferred restore, off the main thread. A newer state (sign-in started or finished,
    /// a 401) wins over this answer.
    private func confirmStoredSignIn(since version: Int) async {
        let store = store
        let signpost = Perf.signposter.beginInterval("launch.keychain")
        let found = await Task.detached(priority: .userInitiated) { () -> (signedIn: Bool, expiresAt: Date?) in
            let signedIn = store.token() != nil
            return (signedIn, signedIn ? store.expiresAt() : nil)
        }.value
        Perf.signposter.endInterval("launch.keychain", signpost)
        guard version == stateVersion, state != .signingIn else { return }
        apply(signedIn: found.signedIn, expiresAt: found.expiresAt)
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
