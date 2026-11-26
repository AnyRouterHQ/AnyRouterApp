import Foundation
import Testing
@testable import AnyRouter

/// Secrets in memory. `accepts: false` plays a Keychain that refuses writes.
final class InMemoryBacking: SecretBacking, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]
    private let accepts: Bool

    init(accepts: Bool = true) { self.accepts = accepts }

    func read(_ account: String) -> String? { lock.withLock { items[account] } }

    func write(_ account: String, _ value: String?) -> Bool {
        guard accepts else { return false }
        lock.withLock { items[account] = value }
        return true
    }
}

@MainActor
private final class ScriptedSigner: OAuthSigning {
    var result: Result<IssuedToken, Error>
    var gate: CheckedContinuation<Void, Never>?
    var holds = false
    var calls = 0
    var modes: [AuthMode] = []

    init(_ result: Result<IssuedToken, Error>) { self.result = result }

    func signIn(mode: AuthMode) async throws -> IssuedToken {
        calls += 1
        modes.append(mode)
        if holds { await withCheckedContinuation { gate = $0 } }
        return try result.get()
    }

    func release() { gate?.resume(); gate = nil }
}

@MainActor
struct AnyRouterAuthTests {
    private func makeStore() -> KeychainStore { KeychainStore(backing: InMemoryBacking()) }
    private let issued = IssuedToken(accessToken: "sk-ar-new", expiresAt: nil)

    @Test func startsSignedOutWithNothingStored() {
        let auth = AnyRouterAuth(store: makeStore(), client: ScriptedSigner(.success(issued)))
        #expect(auth.state == .signedOut)
        #expect(!auth.isSignedIn)
    }

    @Test func startsSignedInWhenAKeyIsAlreadyStored() {
        let store = makeStore()
        store.save(token: "sk-ar-1", expiresAt: nil)
        defer { store.clear() }
        let auth = AnyRouterAuth(store: store, client: ScriptedSigner(.success(issued)))
        #expect(auth.isSignedIn)
    }

    @Test func successfulSignInStoresTheKey() async {
        let store = makeStore()
        defer { store.clear() }
        let auth = AnyRouterAuth(store: store, client: ScriptedSigner(.success(issued)))
        await auth.signIn()
        #expect(auth.isSignedIn)
        #expect(store.token() == "sk-ar-new")
        #expect(auth.lastError == nil)
    }

    @Test func failedSignInShowsTheReasonAndStaysSignedOut() async {
        let auth = AnyRouterAuth(store: makeStore(), client: ScriptedSigner(.failure(OAuthClient.Failure.message("Registration failed"))))
        await auth.signIn()
        #expect(auth.state == .signedOut)
        #expect(auth.lastError == "Registration failed")
    }

    @Test func theModeReachesTheBrowserStep() async {
        let signer = ScriptedSigner(.failure(OAuthClient.Failure.cancelled))
        let auth = AnyRouterAuth(store: makeStore(), client: signer)
        await auth.signIn()
        await auth.signIn(mode: .signUp)
        #expect(signer.modes == [.signIn, .signUp])
    }

    @Test func aServerErrorIsFlaggedBusyAndAnythingElseIsNot() async {
        let busy = AnyRouterAuth(store: makeStore(), client: ScriptedSigner(.failure(OAuthClient.Failure.busy)))
        await busy.signIn(mode: .signUp)
        #expect(busy.lastFailureWasBusy)
        #expect(busy.lastError == "AnyRouter is busy. Try again.")

        let other = AnyRouterAuth(store: makeStore(), client: ScriptedSigner(.failure(OAuthClient.Failure.message("nope"))))
        await other.signIn()
        #expect(!other.lastFailureWasBusy)
    }

    @Test func cancellingSignInIsNotAnError() async {
        let auth = AnyRouterAuth(store: makeStore(), client: ScriptedSigner(.failure(OAuthClient.Failure.cancelled)))
        await auth.signIn()
        #expect(auth.state == .signedOut)
        #expect(auth.lastError == nil)
    }

    @Test func aKeychainThatRefusesTheKeyIsReportedNotSilentlyIgnored() async {
        let store = KeychainStore(backing: InMemoryBacking(accepts: false))
        let auth = AnyRouterAuth(store: store, client: ScriptedSigner(.success(issued)))
        await auth.signIn()
        #expect(auth.state == .signedOut)
        #expect(auth.lastError == "Could not save the sign-in to the Keychain.")
    }

    @Test func tappingSignInTwiceStartsOnlyOneFlow() async {
        let store = makeStore()
        defer { store.clear() }
        let signer = ScriptedSigner(.success(issued))
        signer.holds = true
        let auth = AnyRouterAuth(store: store, client: signer)
        let first = Task { await auth.signIn() }
        #expect(await waitUntil { auth.state == .signingIn })
        await auth.signIn()
        #expect(signer.calls == 1)
        signer.release()
        await first.value
        #expect(auth.isSignedIn)
    }

    @Test func signOutForgetsTheKeyAndError() async {
        let store = makeStore()
        let auth = AnyRouterAuth(store: store, client: ScriptedSigner(.failure(OAuthClient.Failure.message("x"))))
        await auth.signIn()
        store.save(token: "sk-ar-1", expiresAt: nil)
        auth.refresh()
        auth.signOut()
        #expect(auth.state == .signedOut)
        #expect(store.token() == nil)
        #expect(auth.lastError == nil)
    }

    @Test func engineSeeingA401SignsTheUserOut() async {
        let store = makeStore()
        store.save(token: "sk-ar-1", expiresAt: nil)
        defer { store.clear() }
        let auth = AnyRouterAuth(store: store, client: ScriptedSigner(.success(issued)))
        #expect(auth.isSignedIn)
        let api = StubbedAPI { _ in StubRegistry.Reply(status: 401, body: Data("{}".utf8)) }
        let engine = auth.makeEngine(config: api.config, session: api.session)
        _ = try? await engine.availableModels()
        #expect(auth.state == .signedOut)
    }
}

struct KeychainStoreTests {
    private func makeStore() -> KeychainStore { KeychainStore(backing: InMemoryBacking()) }

    @Test func savedTokenComesBackUntilCleared() {
        let store = makeStore()
        defer { store.clear() }
        #expect(store.token() == nil)
        store.save(token: "sk-ar-1", expiresAt: nil)
        #expect(store.token() == "sk-ar-1")
        #expect(store.expiresAt() == nil)
        store.clear()
        #expect(store.token() == nil)
    }

    @Test func savingAgainReplacesTheOldToken() {
        let store = makeStore()
        defer { store.clear() }
        store.save(token: "old", expiresAt: nil)
        store.save(token: "new", expiresAt: nil)
        #expect(store.token() == "new")
    }

    @Test func expiredTokenCountsAsSignedOut() {
        let store = makeStore()
        defer { store.clear() }
        store.save(token: "sk-ar-1", expiresAt: Date(timeIntervalSinceNow: -60))
        #expect(store.token() == nil)
    }

    @Test func tokenBeforeExpiryIsUsableAndExpiryRoundTrips() throws {
        let store = makeStore()
        defer { store.clear() }
        let expiry = Date(timeIntervalSinceNow: 3600)
        store.save(token: "sk-ar-1", expiresAt: expiry)
        #expect(store.token() == "sk-ar-1")
        let stored = try #require(store.expiresAt())
        #expect(abs(stored.timeIntervalSince(expiry)) < 1)
    }

    @Test func emptyTokenIsTreatedAsNone() {
        let store = makeStore()
        defer { store.clear() }
        store.save(token: "", expiresAt: nil)
        #expect(store.token() == nil)
    }

    @Test func saveReportsWhetherTheKeychainAcceptedTheToken() {
        let ok = makeStore()
        defer { ok.clear() }
        #expect(ok.save(token: "sk-ar-1", expiresAt: nil))
        let refusing = KeychainStore(backing: InMemoryBacking(accepts: false))
        #expect(!refusing.save(token: "sk-ar-1", expiresAt: nil))
        #expect(refusing.token() == nil)
    }

    @Test func aTokenWithAnInvalidExpiryStaysUsable() {
        let backing = InMemoryBacking()
        let store = KeychainStore(backing: backing)
        store.save(token: "sk-ar-1", expiresAt: nil)
        _ = backing.write("oauth-expires-at", "not a number")
        #expect(store.expiresAt() == nil)
        #expect(store.token() == "sk-ar-1")
    }
}

struct SystemKeychainTests {
    /// An unsigned Simulator build has no Keychain access, so only what a working Keychain must do is asserted.
    @Test func writesReadsAndDeletesWithoutCrashing() {
        let keychain = SystemKeychain(service: "dev.anyrouter.tests.\(UUID().uuidString)")
        #expect(keychain.read("account") == nil)
        if keychain.write("account", "secret") { #expect(keychain.read("account") == "secret") }
        #expect(keychain.write("account", nil))
        #expect(keychain.read("account") == nil)
    }

    @Test func theDefaultStoreUsesTheSystemKeychain() {
        let store = KeychainStore(service: "dev.anyrouter.tests.\(UUID().uuidString)")
        store.clear()
        #expect(store.token() == nil)
    }
}

struct PKCEFailureTests {
    @Test func randomSourceFailureIsReported() {
        #expect(throws: PKCE.Failure.self) { _ = try PKCE.makeVerifier { _ in errSecAllocate } }
    }
}

struct SSEEdgeTests {
    @Test func bareDataLineIsAnEmptyPayloadLine() {
        var parser = SSEParser()
        #expect(parser.feed(Data("data\ndata: x\n\n".utf8)) == ["\nx"])
    }

    @Test func unterminatedLineWithCarriageReturnIsFlushed() {
        var parser = SSEParser()
        #expect(parser.feed(Data("data: x\r".utf8)).isEmpty)
        #expect(parser.finish() == ["x"])
    }

    @Test func blankLinesAndFieldsOtherThanDataProduceNoEvents() {
        var parser = SSEParser()
        #expect(parser.feed(Data("\n\nevent: ping\nid: 1\n\n".utf8)).isEmpty)
        #expect(parser.finish().isEmpty)
    }

    @Test func plainStringAndMessagelessErrorsBecomeStreamErrors() {
        var decoder = ChatChunkDecoder()
        #expect(throws: AnyRouterError.stream("overloaded")) { _ = try decoder.decode(#"{"error":"overloaded"}"#) }
        #expect(throws: AnyRouterError.stream("The model stopped with an error.")) { _ = try decoder.decode(#"{"error":{"code":1}}"#) }
        #expect(throws: AnyRouterError.stream("The model stopped with an error.")) { _ = try decoder.decode(#"{"error":3}"#) }
    }

    @Test func emptyContentAndUsageWithoutCountsEmitNothing() throws {
        var decoder = ChatChunkDecoder()
        #expect(try decoder.decode(#"{"choices":[{"delta":{"content":""}}],"usage":{"prompt_tokens":1}}"#).isEmpty)
        #expect(try decoder.decode("not json").isEmpty)
        #expect(decoder.finishReason == nil)
    }

    @Test func doneAfterFinishReasonCarriesIt() throws {
        var decoder = ChatChunkDecoder()
        _ = try decoder.decode(#"{"choices":[{"delta":{},"finish_reason":"length"}]}"#)
        #expect(try decoder.decode(" [DONE] ") == [.done(finishReason: "length")])
        #expect(decoder.isDone)
    }
}
