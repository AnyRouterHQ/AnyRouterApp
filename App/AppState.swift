import Observation
import UIKit

/// App-wide state and dependency root. Lanes register their engines and services here.
@MainActor @Observable
final class AppState {
    let registry = EngineRegistry()
    let settings: AppSettings
    let presets = PresetStore()
    let models: ModelStore
    /// Sign-in state for AnyRouter cloud models.
    var account: any AccountService
    /// Local model catalog and downloads.
    var hub: any ModelHubService

    init() {
        if DemoData.isEnabled {
            let demo = DemoData.install(registry: registry)
            settings = demo.settings
            models = demo.models
            account = demo.account
            hub = demo.hub
            return
        }
        settings = AppSettings()
        models = ModelStore(registry: registry)
        let gguf = GGUFEngine()
        let mlx = MLXEngine()
        registry.register(AppleFoundationEngine())
        registry.register(gguf)
        registry.register(mlx)
        // A loaded model is several GB; hand it back when the system is short on memory.
        // A running generation keeps its own reference, so this never cuts a reply short.
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { _ in
            Task {
                await gguf.unload()
                await mlx.unload()
            }
        }
        let auth = AnyRouterAuth()
        registry.register(auth.makeEngine())
        account = AnyRouterAccountAdapter(auth: auth)
        hub = LocalModelHub()
    }
}
