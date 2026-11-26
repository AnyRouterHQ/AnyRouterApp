import Observation

/// App-wide state and dependency root. Lanes register their engines and services here.
@MainActor @Observable
final class AppState {
    let registry = EngineRegistry()
    let settings = AppSettings()
    let models: ModelStore
    /// Sign-in state for AnyRouter cloud models.
    var account: any AccountService = UnavailableAccountService()
    /// Local model catalog and downloads. Lane C replaces the default.
    var hub: any ModelHubService = EmptyModelHubService()

    init() {
        models = ModelStore(registry: registry)
        registry.register(AppleFoundationEngine())
        let auth = AnyRouterAuth()
        registry.register(auth.makeEngine())
        account = AnyRouterAccountAdapter(auth: auth)
    }
}
