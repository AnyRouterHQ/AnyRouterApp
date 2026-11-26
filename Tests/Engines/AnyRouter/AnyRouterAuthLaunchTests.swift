import Foundation
import Testing
@testable import AnyRouter

/// A token store that never touches the Keychain. It counts reads and notes whether any ran on the main thread.
final class SpyTokenStore: AuthTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String?]
    private var readCount = 0
    private var mainReads = 0
    private let expiry: Date?

    /// `tokens` answer successive `token()` calls; the last answer repeats.
    init(tokens: [String?], expiry: Date? = nil) {
        answers = tokens
        self.expiry = expiry
    }

    var reads: Int { lock.withLock { readCount } }
    var readOnMain: Bool { lock.withLock { mainReads > 0 } }

    private func noteRead() {
        readCount += 1
        if Thread.isMainThread { mainReads += 1 }
    }

    func token() -> String? {
        lock.withLock {
            noteRead()
            let index = min(readCount - 1, answers.count - 1)
            return answers[index]
        }
    }

    func expiresAt() -> Date? {
        lock.withLock {
            noteRead()
            return expiry
        }
    }

    func save(token: String, expiresAt: Date?) -> Bool { true }

    func clear() {
        lock.withLock { answers = [nil] }
    }
}

@MainActor
private final class HeldSigner: OAuthSigning {
    private var gate: CheckedContinuation<Void, Never>?

    func signIn(mode: AuthMode) async throws -> IssuedToken {
        await withCheckedContinuation { gate = $0 }
        return IssuedToken(accessToken: "t", expiresAt: nil)
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
private final class ChangeLog {
    var values: [Bool] = []
}

@MainActor
struct AnyRouterAuthLaunchTests {
    private func hints(signedIn: Bool?, expiry: Date? = nil) -> UserDefaults {
        let defaults = testDefaults()
        if let signedIn { defaults.set(signedIn, forKey: AnyRouterAuth.signedInHintKey) }
        if let expiry { defaults.set(expiry.timeIntervalSince1970, forKey: AnyRouterAuth.expiryHintKey) }
        return defaults
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(150))
    }

    @Test func deferredRestoreReadsNothingOnTheCallingThreadThenReadsOffMain() async {
        let store = SpyTokenStore(tokens: ["tok"])
        let auth = AnyRouterAuth(store: store, client: HeldSigner(), restore: .deferred, hints: hints(signedIn: true))
        #expect(store.reads == 0, "init must not touch the Keychain")
        #expect(auth.isSignedIn, "the remembered state shows at once")
        #expect(await waitUntil { store.reads > 0 })
        #expect(!store.readOnMain, "the Keychain read runs off the main thread")
    }

    @Test func withoutAHintTheKeychainAnswerSignsIn() async {
        let log = ChangeLog()
        let auth = AnyRouterAuth(
            store: SpyTokenStore(tokens: ["tok"]), client: HeldSigner(), restore: .deferred, hints: hints(signedIn: nil))
        auth.onSignedInChange = { log.values.append($0) }
        #expect(!auth.isSignedIn)
        #expect(await waitUntil { auth.isSignedIn })
        #expect(log.values == [true])
    }

    @Test func aStaleHintIsCorrectedAndForgotten() async {
        let log = ChangeLog()
        let defaults = hints(signedIn: true, expiry: Date().addingTimeInterval(3600))
        let auth = AnyRouterAuth(
            store: SpyTokenStore(tokens: [nil]), client: HeldSigner(), restore: .deferred, hints: defaults)
        auth.onSignedInChange = { log.values.append($0) }
        #expect(auth.isSignedIn)
        #expect(await waitUntil { !auth.isSignedIn })
        #expect(log.values == [false])
        #expect(defaults.bool(forKey: AnyRouterAuth.signedInHintKey) == false)
        #expect(defaults.object(forKey: AnyRouterAuth.expiryHintKey) == nil)
    }

    @Test func aMatchingHintStaysSignedInWithoutAChange() async {
        let log = ChangeLog()
        let expiry = Date().addingTimeInterval(3600)
        let store = SpyTokenStore(tokens: ["tok"], expiry: expiry)
        let auth = AnyRouterAuth(
            store: store, client: HeldSigner(), restore: .deferred, hints: hints(signedIn: true, expiry: expiry))
        auth.onSignedInChange = { log.values.append($0) }
        #expect(await waitUntil { store.reads >= 2 })
        await settle()
        #expect(auth.state == .signedIn(expiresAt: Date(timeIntervalSince1970: expiry.timeIntervalSince1970)))
        #expect(log.values.isEmpty)
    }

    @Test func aHintPastItsExpiryStartsSignedOut() {
        let auth = AnyRouterAuth(
            store: SpyTokenStore(tokens: [nil]), client: HeldSigner(), restore: .deferred,
            hints: hints(signedIn: true, expiry: Date().addingTimeInterval(-60)))
        #expect(!auth.isSignedIn)
    }

    @Test func aStateAppliedBeforeTheAnswerArrivesWins() async {
        // The sync refresh reads "tok"; the late deferred read would say nil.
        let store = SpyTokenStore(tokens: ["tok", nil])
        let auth = AnyRouterAuth(store: store, client: HeldSigner(), restore: .deferred, hints: hints(signedIn: nil))
        auth.refresh()
        #expect(auth.isSignedIn)
        #expect(await waitUntil { store.reads >= 3 })
        await settle()
        #expect(auth.isSignedIn, "a stale Keychain answer must not undo a newer state")
    }

    @Test func aSignInInProgressIsNotOverwritten() async {
        let signer = HeldSigner()
        let store = SpyTokenStore(tokens: [nil])
        let auth = AnyRouterAuth(store: store, client: signer, restore: .deferred, hints: hints(signedIn: nil))
        let signing = Task { await auth.signIn() }
        #expect(await waitUntil { auth.state == .signingIn })
        #expect(await waitUntil { store.reads > 0 })
        await settle()
        #expect(auth.state == .signingIn)
        signer.release()
        await signing.value
    }

    @Test func immediateRestoreStillReadsAtOnceAndKeepsNoHint() {
        let store = SpyTokenStore(tokens: ["tok"])
        let auth = AnyRouterAuth(store: store, client: HeldSigner())
        #expect(store.reads > 0)
        #expect(auth.isSignedIn)
    }
}
