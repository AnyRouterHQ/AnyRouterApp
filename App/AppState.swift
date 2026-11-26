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
    /// App memory and the loaded local model, with unload.
    let memory: MemoryMonitor
    /// Tool servers (AnyRouter MCP and custom ones).
    let integrations: IntegrationsStore
    /// Typed questions answered by decision models.
    let decisions: DecisionsStore

    init() {
        let tokenStore = KeychainStore()
        integrations = IntegrationsStore(anyRouterToken: { tokenStore.token() })
        if DemoData.isEnabled {
            let demo = DemoData.install(registry: registry)
            settings = demo.settings
            models = demo.models
            account = demo.account
            hub = demo.hub
            memory = MemoryMonitor.inert()
            decisions = DecisionsStore(service: DemoDecisionsService())
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
        memory = MemoryMonitor(
            read: {
                let snapshot = MemorySnapshot.read()
                return MemoryReadout(footprintBytes: snapshot.footprintBytes, availableBytes: snapshot.availableBytes)
            },
            loaded: {
                if let id = await gguf.loadedModelID() { return id }
                return await mlx.loadedModelID()
            },
            unload: {
                await gguf.unload()
                await mlx.unload()
            })
        let auth = AnyRouterAuth()
        let anyRouter = auth.makeEngine()
        registry.register(anyRouter)
        decisions = DecisionsStore(service: AnyRouterDecisionsAdapter(engine: anyRouter))
        account = AnyRouterAccountAdapter(auth: auth)
        hub = LocalModelHub()
    }
}
