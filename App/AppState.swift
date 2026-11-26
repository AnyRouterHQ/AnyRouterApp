import Observation

/// App-wide state and dependency root. Lanes register their engines and services here.
@MainActor @Observable
final class AppState {
    let registry = EngineRegistry()
    /// Sign-in state for AnyRouter cloud models. Lane B replaces the default.
    var account: any AccountService = UnavailableAccountService()
    /// Local model catalog and downloads. Lane C replaces the default.
    var hub: any ModelHubService = EmptyModelHubService()

    init() {}
}
