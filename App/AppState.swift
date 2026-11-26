import Observation

/// App-wide state and dependency root. Lanes register their engines here.
@MainActor @Observable
final class AppState {
    let registry = EngineRegistry()

    init() {}
}
