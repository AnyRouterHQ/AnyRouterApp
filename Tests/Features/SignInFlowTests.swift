import Foundation
import Testing
@testable import AnyRouter

struct SignInFlowTests {
    private typealias Flow = SignInFlow
    private func run(_ events: [Flow.Event], from start: Flow.State = .signedOut) -> Flow.State {
        events.reduce(start) { Flow.reduce($0, $1) }
    }

    @Test func signInThenKeyIsSignedInAndVerified() {
        #expect(run([.start(.signIn)]) == .authorizing(.signIn))
        #expect(run([.start(.signIn), .succeeded(emailVerified: true)]) == .signedIn(.verified))
    }

    @Test func aNewAccountComesBackSignedInWithoutASecondLogin() {
        // Create account is one authorize flow: start(signUp) then the key, no extra sign-in step between.
        #expect(run([.start(.signUp), .succeeded(emailVerified: false)]) == .signedIn(.unverified))
    }

    @Test func anUnverifiedEmailIsSignedInNotAFailure() {
        let state = run([.start(.signUp), .succeeded(emailVerified: false)])
        #expect(state == .signedIn(.unverified))
        if case .failed = state { Issue.record("unverified must not be a failure") }
    }

    @Test func aServerThatDoesNotSayCountsAsVerified() {
        #expect(run([.start(.signIn), .succeeded(emailVerified: nil)]) == .signedIn(.verified))
    }

    @Test func cancellingGoesBackToSignedOutWithoutAnError() {
        #expect(run([.start(.signUp), .cancelled]) == .signedOut)
    }

    @Test func aBusyServerFailsWithTheModeToRetryAndRetryReopensTheSameFlow() {
        let failed = run([.start(.signUp), .failed(.busy)])
        #expect(failed == .failed(.busy, retry: .signUp))
        #expect(Flow.FailureReason.busy.text == "AnyRouter is busy. Try again in a moment.")
        // Try again: same mode, then it can succeed.
        let again = run([.start(.signUp)], from: failed)
        #expect(again == .authorizing(.signUp))
        #expect(run([.succeeded(emailVerified: true)], from: again) == .signedIn(.verified))
    }

    @Test func aFailureKeepsTheServerMessage() {
        let state = run([.start(.signIn), .failed(.message("Registration failed"))])
        #expect(state == .failed(.message("Registration failed"), retry: .signIn))
        #expect(Flow.FailureReason.message("Registration failed").text == "Registration failed")
    }

    @Test func afterAFailureThePersonCanPickTheOtherDoor() {
        let failed: Flow.State = .failed(.busy, retry: .signIn)
        #expect(run([.start(.signUp)], from: failed) == .authorizing(.signUp))
    }

    @Test func aSecondTapWhileTheSheetIsOpenChangesNothing() {
        let open: Flow.State = .authorizing(.signIn)
        #expect(run([.start(.signUp)], from: open) == open)
        #expect(run([.start(.signIn)], from: .signedIn(.verified)) == .signedIn(.verified))
    }

    @Test func lateAnswersAfterTheFlowEndedAreIgnored() {
        #expect(run([.succeeded(emailVerified: true)]) == .signedOut)
        #expect(run([.cancelled, .failed(.busy)]) == .signedOut)
        #expect(run([.cancelled], from: .signedIn(.unverified)) == .signedIn(.unverified))
    }

    @Test func signingOutOrARefusedKeyResetsFromAnyState() {
        let states: [Flow.State] = [.signedIn(.unverified), .authorizing(.signUp), .failed(.busy, retry: .signIn)]
        for state in states {
            #expect(run([.signedOut], from: state) == .signedOut)
        }
    }

    @Test func onDeviceGoesStraightToChatWhenAppleIsThereElseToTheLocalStep() {
        #expect(OnboardingLogic.onDeviceRoute(appleAvailable: true) == .chat(.apple))
        #expect(OnboardingLogic.onDeviceRoute(appleAvailable: false) == .pickLocal)
    }
}

// MARK: Adapter: how a browser result reaches the flow

private final class MemoryTokenStore: AuthTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    func token() -> String? { lock.withLock { stored } }
    func expiresAt() -> Date? { nil }
    func save(token: String, expiresAt: Date?) -> Bool { lock.withLock { stored = token }; return true }
    func clear() { lock.withLock { stored = nil } }
}

@MainActor
private final class StubBrowser: OAuthSigning {
    var result: Result<IssuedToken, Error>
    private(set) var modes: [AuthMode] = []
    init(_ result: Result<IssuedToken, Error>) { self.result = result }
    func signIn(mode: AuthMode) async throws -> IssuedToken {
        modes.append(mode)
        return try result.get()
    }
}

@MainActor
struct AccountSignUpTests {
    private func adapter(_ browser: StubBrowser) -> AnyRouterAccountAdapter {
        AnyRouterAccountAdapter(auth: AnyRouterAuth(store: MemoryTokenStore(), client: browser))
    }

    @Test func createAccountSignsInWithTheSameKey() async throws {
        let browser = StubBrowser(.success(IssuedToken(accessToken: "sk-ar-new", expiresAt: nil)))
        let account = adapter(browser)
        try await account.signIn(mode: .signUp)
        #expect(browser.modes == [.signUp])
        #expect(account.state.isSignedIn)
    }

    @Test func theDefaultSignInUsesTheSignInPage() async throws {
        let browser = StubBrowser(.success(IssuedToken(accessToken: "sk-ar-new", expiresAt: nil)))
        try await adapter(browser).signIn()
        #expect(browser.modes == [.signIn])
    }

    @Test func closingTheSheetReturnsWithoutAnErrorAndStaysSignedOut() async throws {
        let account = adapter(StubBrowser(.failure(OAuthClient.Failure.cancelled)))
        try await account.signIn(mode: .signUp)
        #expect(!account.state.isSignedIn)
    }

    @Test func aBusyServerThrowsAnErrorTheScreenCanRetry() async {
        let account = adapter(StubBrowser(.failure(OAuthClient.Failure.busy)))
        do {
            try await account.signIn(mode: .signUp)
            Issue.record("expected a failure")
        } catch let error as AnyRouterAccountAdapter.SignInFailed {
            #expect(error.isBusy)
        } catch {
            Issue.record("wrong error \(error)")
        }
    }

    @Test func anyOtherFailureIsNotBusy() async {
        let account = adapter(StubBrowser(.failure(OAuthClient.Failure.message("nope"))))
        do {
            try await account.signIn()
            Issue.record("expected a failure")
        } catch let error as AnyRouterAccountAdapter.SignInFailed {
            #expect(!error.isBusy)
            #expect(error.message == "nope")
        } catch {
            Issue.record("wrong error \(error)")
        }
    }
}
