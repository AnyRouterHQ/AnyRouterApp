import Foundation
import Testing
@testable import AnyRouter

private final class StartSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(dsn: String, onMain: Bool)] = []

    var count: Int { lock.withLock { calls.count } }
    var anyOnMain: Bool { lock.withLock { calls.contains { $0.onMain } } }
    var dsns: [String] { lock.withLock { calls.map(\.dsn) } }

    func record(_ dsn: String) {
        lock.withLock { calls.append((dsn, Thread.isMainThread)) }
    }
}

/// Launch must not wait for the Keychain or for the Sentry SDK.
@MainActor
struct LaunchPathTests {
    private let dsn = "https://k@h.example.io/1"

    @Test func appStateInitReadsNoKeychainAndStartsNoSentryBeforeItReturns() async {
        let store = SpyTokenStore(tokens: [nil])
        let starts = StartSpy()
        let state = AppState(dependencies: LaunchDependencies(
            tokenStore: store, hints: testDefaults(),
            makeTelemetry: {
                Diagnostics.makeTelemetry(dsn: dsn, shares: { true }, startSDK: { dsn, _ in starts.record(dsn) })
            }))
        #expect(store.reads == 0, "AppState.init must not read the Keychain")
        #expect(starts.count == 0, "AppState.init must not start Sentry")
        if case .signedOut = state.account.state {} else { Issue.record("no hint, so the first state is signed out") }

        #expect(await waitUntil { store.reads > 0 }, "the Keychain is read after launch")
        #expect(!store.readOnMain)
        #expect(await waitUntil { starts.count == 1 }, "Sentry starts after launch")
        #expect(!starts.anyOnMain, "and off the main thread")
        #expect(starts.dsns == [dsn])
    }

    @Test func sentryStartsOnceOffMainAfterTheDelay() async {
        let starts = StartSpy()
        _ = Diagnostics.makeTelemetry(dsn: dsn, shares: { true }, startSDK: { dsn, _ in starts.record(dsn) })
        #expect(starts.count == 0)
        #expect(await waitUntil { starts.count == 1 })
        #expect(!starts.anyOnMain)
    }

    @Test func sentryNeverStartsWhenSharingIsOffOrThereIsNoDSN() async {
        let starts = StartSpy()
        _ = Diagnostics.makeTelemetry(dsn: dsn, shares: { false }, startSDK: { dsn, _ in starts.record(dsn) })
        _ = Diagnostics.makeTelemetry(dsn: "", shares: { true }, startSDK: { dsn, _ in starts.record(dsn) })
        _ = Diagnostics.makeTelemetry(dsn: nil, shares: { true }, startSDK: { dsn, _ in starts.record(dsn) })
        try? await Task.sleep(for: Diagnostics.sentryStartDelay + .milliseconds(400))
        #expect(starts.count == 0)
    }
}
