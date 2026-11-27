import Foundation
import Testing
@testable import AnyRouter

/// The account card and the cloud list show the last known values at launch, then refresh. Nothing of a signed-out
/// person, and never the token, is left behind.
@MainActor
struct AccountSummaryCacheTests {
    private let me = Data(#"{"name":"Ada","email":"ada@example.com","balance":7.5}"#.utf8)

    private func loader(status: Int = 200, body: Data? = nil) -> AccountSummaryLoader {
        let answer = body ?? me
        return AccountSummaryLoader(fetch: { request in
            request.url?.lastPathComponent == "me" ? (answer, status) : (Data(), 403)
        })
    }

    private func signedIn() -> AnyRouterAuth {
        AnyRouterAuth(store: SpyTokenStore(tokens: ["sk-ar-secret"]))
    }

    @Test func aRefreshSavesTheSummaryAndTheNextLaunchShowsItAtOnce() async throws {
        let defaults = testDefaults()
        let first = AnyRouterAccountAdapter(auth: signedIn(), loader: loader(), cache: defaults)
        await first.refreshSummary()
        #expect(first.summary?.title == "Ada")

        let next = AnyRouterAccountAdapter(auth: signedIn(), loader: loader(status: 500), cache: defaults)
        #expect(next.summary?.title == "Ada", "shown before any network call")
        #expect(next.summary?.credits?.balance == 7.5)
    }

    @Test func theCacheNeverHoldsTheToken() async throws {
        let defaults = testDefaults()
        let adapter = AnyRouterAccountAdapter(auth: signedIn(), loader: loader(), cache: defaults)
        await adapter.refreshSummary()
        let stored = try #require(defaults.data(forKey: AnyRouterAccountAdapter.summaryCacheKey))
        #expect(!String(decoding: stored, as: UTF8.self).contains("sk-ar-secret"))
    }

    @Test func aFreshSummaryReplacesTheCachedOne() async throws {
        let defaults = testDefaults()
        await AnyRouterAccountAdapter(auth: signedIn(), loader: loader(), cache: defaults).refreshSummary()
        let renamed = Data(#"{"name":"Grace"}"#.utf8)
        let next = AnyRouterAccountAdapter(auth: signedIn(), loader: loader(body: renamed), cache: defaults)
        #expect(next.summary?.title == "Ada")
        await next.refreshSummary()
        #expect(next.summary?.title == "Grace")
        #expect(AnyRouterAccountAdapter(auth: signedIn(), cache: defaults).summary?.title == "Grace")
    }

    @Test func aFailedRefreshKeepsTheCachedSummary() async throws {
        let defaults = testDefaults()
        await AnyRouterAccountAdapter(auth: signedIn(), loader: loader(), cache: defaults).refreshSummary()
        let next = AnyRouterAccountAdapter(auth: signedIn(), loader: loader(status: 503), cache: defaults)
        await next.refreshSummary()
        #expect(next.summary?.title == "Ada")
    }

    @Test func signingOutClearsTheCache() async throws {
        let defaults = testDefaults()
        let adapter = AnyRouterAccountAdapter(auth: signedIn(), loader: loader(), cache: defaults)
        await adapter.refreshSummary()
        await adapter.signOut()
        #expect(adapter.summary == nil)
        #expect(defaults.data(forKey: AnyRouterAccountAdapter.summaryCacheKey) == nil)
        #expect(AnyRouterAccountAdapter(auth: signedIn(), cache: defaults).summary == nil)
    }

    @Test func aRefusedKeyClearsTheCacheThroughTheSignedInChange() async throws {
        let defaults = testDefaults()
        let auth = signedIn()
        let adapter = AnyRouterAccountAdapter(auth: auth, loader: loader(), cache: defaults)
        auth.onSignedInChange = { if !$0 { adapter.forgetSummary() } }
        await adapter.refreshSummary()
        auth.handleUnauthorized()
        #expect(adapter.summary == nil)
        #expect(defaults.data(forKey: AnyRouterAccountAdapter.summaryCacheKey) == nil)
    }

    @Test func aSignedOutLaunchShowsNoCachedSummary() async throws {
        let defaults = testDefaults()
        await AnyRouterAccountAdapter(auth: signedIn(), loader: loader(), cache: defaults).refreshSummary()
        let signedOut = AnyRouterAuth(store: SpyTokenStore(tokens: [nil]))
        #expect(AnyRouterAccountAdapter(auth: signedOut, cache: defaults).summary == nil)
    }
}

@MainActor
struct CloudListCacheTests {
    private func cloud(_ id: String) -> ModelDescriptor {
        ModelDescriptor(id: id, source: .anyrouter, displayName: id, contextLength: nil, capabilities: ["chat"], sizeBytes: nil, isInstalled: true)
    }

    private func store(_ defaults: UserDefaults, cloud models: [ModelDescriptor], fails: Bool = false) -> ModelStore {
        let registry = EngineRegistry()
        let script = ListingScript()
        script.fails = fails
        registry.register(ScriptedListingEngine(source: .anyrouter, models: models, script: script))
        return ModelStore(registry: registry, defaults: defaults)
    }

    @Test func theNextLaunchShowsTheLastCloudListBeforeAnyRefresh() async {
        let defaults = testDefaults()
        await store(defaults, cloud: [cloud("a/one"), cloud("b/two")]).refresh()
        let next = store(defaults, cloud: [], fails: true)
        #expect(next.models.map(\.id) == ["a/one", "b/two"])
    }

    @Test func aRefreshReplacesTheCachedList() async {
        let defaults = testDefaults()
        await store(defaults, cloud: [cloud("a/one")]).refresh()
        let next = store(defaults, cloud: [cloud("c/three")])
        await next.refresh()
        #expect(next.models.map(\.id) == ["c/three"])
        #expect(store(defaults, cloud: []).models.map(\.id) == ["c/three"])
    }

    @Test func aFailedRefreshKeepsTheCachedList() async {
        let defaults = testDefaults()
        await store(defaults, cloud: [cloud("a/one")]).refresh()
        let next = store(defaults, cloud: [], fails: true)
        await next.refresh()
        #expect(next.models.map(\.id) == ["a/one"])
    }

    @Test func forgettingTheListClearsItNowAndOnTheNextLaunch() async {
        let defaults = testDefaults()
        let models = store(defaults, cloud: [cloud("a/one")])
        await models.refresh()
        models.forgetCloudList()
        #expect(models.models.isEmpty)
        #expect(store(defaults, cloud: []).models.isEmpty)
    }
}
