import Observation
import UIKit

/// The pieces of launch that touch the Keychain, the network SDKs or UserDefaults, injectable so a test can
/// prove none of them does blocking work inside `AppState.init`.
struct LaunchDependencies {
    var tokenStore: any AuthTokenStore = LaunchDependencies.defaultTokenStore()
    /// Remembers the sign-in state between launches, so the UI can show it before the Keychain answers.
    var hints: UserDefaults = .standard
    var makeTelemetry: @MainActor () -> any Telemetry = { Diagnostics.makeTelemetry() }
}

extension LaunchDependencies {
    /// The Keychain, except in a Debug UI end-to-end run that passes `-ARTestAPIKey`.
    static func defaultTokenStore() -> any AuthTokenStore {
        #if DEBUG
        if let injected = E2ETokenStore.fromLaunchArguments() { return injected }
        #endif
        return KeychainStore()
    }
}

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
    /// Loads a local model's weights ahead of the first message. Called after launch, never before the first frame.
    let warmUp: @Sendable (ModelDescriptor) async -> Void
    /// Tool servers (AnyRouter MCP and custom ones).
    let integrations: IntegrationsStore
    /// Built-in tools, the AnyRouter MCP server and custom servers, merged for chat and Settings.
    let tools: ToolRegistry
    /// The tool approval sheet's queue.
    let toolApprovals = ToolApprovalCenter()
    /// Voice engines, voice models and their settings, and the one dictation session (there is one microphone).
    let voice = VoiceHub()
    let dictation = DictationController()
    /// Reads replies aloud.
    let speaker = ReplySpeaker()
    /// Whether the device has a connection: offline, cloud models and web tools are skipped.
    let network = NetworkStatus()
    /// Typed questions answered by decision models.
    let decisions: DecisionsStore
    /// The one reporting door. Views and engines call this, never a vendor SDK.
    let telemetry: any Telemetry
    /// Saved crash, hang and metric payloads (Settings, Diagnostics).
    let diagnostics = DiagnosticsStore()
    @ObservationIgnored private var metricKit: MetricKitReporter?

    init(dependencies: LaunchDependencies = LaunchDependencies()) {
        // First, so a stall anywhere in launch is recorded (Settings > Diagnostics).
        MainThreadWatchdog.shared.start()
        let launchSignpost = Perf.signposter.beginInterval("launch.appstate")
        defer { Perf.signposter.endInterval("launch.appstate", launchSignpost) }
        let tokenStore = dependencies.tokenStore
        // Files that were picked but never sent are not kept across launches.
        if !DemoData.isEnabled { Task.detached { AttachmentStore.shared.purgePending() } }
        let integrations = IntegrationsStore(anyRouterToken: { tokenStore.token() })
        self.integrations = integrations
        tools = ToolRegistry(integrations: integrations, publicSources: ToolSourceCatalog.publicSources)
        if DemoData.isEnabled {
            telemetry = NoopTelemetry()
            let demo = DemoData.install(registry: registry)
            settings = demo.settings
            models = demo.models
            account = demo.account
            hub = demo.hub
            memory = MemoryMonitor.inert()
            warmUp = { _ in }
            decisions = DecisionsStore(service: DemoDecisionsService())
            return
        }
        let telemetry = dependencies.makeTelemetry()
        self.telemetry = telemetry
        settings = AppSettings()
        models = ModelStore(registry: registry, telemetry: telemetry, usage: AnyRouterWeeklyUsage())
        let enginesSignpost = Perf.signposter.beginInterval("launch.engines")
        // One gate and one loaded model for both local engines: a phone has room for one of each.
        let residency = LocalResidency(telemetry: telemetry)
        let gguf = GGUFEngine(telemetry: telemetry, residency: residency)
        let mlx = MLXEngine(telemetry: telemetry, residency: residency)
        registry.register(AppleFoundationEngine())
        registry.register(gguf)
        registry.register(mlx)
        Perf.signposter.endInterval("launch.engines", enginesSignpost)
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
        warmUp = { model in
            if model.source == .gguf { await gguf.warm(model: model) }
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
            },
            diagnostics: {
                let snapshot = MemorySnapshot.read()
                return MemoryDiagnostics(
                    footprintBytes: snapshot.footprintBytes, availableBytes: snapshot.availableBytes,
                    physicalBytes: snapshot.physicalBytes, budgetBytes: snapshot.deviceMemory.budgetBytes,
                    limitBytes: snapshot.processLimitBytes, entitlementSigned: MemoryEntitlement.isSignedForThisApp())
            })
        // The Keychain is read off the main thread after launch; the first frame shows the remembered state.
        let authSignpost = Perf.signposter.beginInterval("launch.auth")
        let auth = AnyRouterAuth(store: tokenStore, restore: .deferred, hints: dependencies.hints)
        Perf.signposter.endInterval("launch.auth", authSignpost)
        // Signing in connects the AnyRouter MCP server with the same token; signing out disconnects it.
        auth.onSignedInChange = { [integrations] in _ = integrations.accountChanged(signedIn: $0) }
        if auth.isSignedIn { _ = integrations.accountChanged(signedIn: true) }
        let anyRouter = auth.makeEngine()
        registry.register(anyRouter)
        decisions = DecisionsStore(service: AnyRouterDecisionsAdapter(engine: anyRouter))
        account = AnyRouterAccountAdapter(auth: auth, telemetry: telemetry)
        let hubSignpost = Perf.signposter.beginInterval("launch.hub")
        hub = LocalModelHub(
            downloads: ModelDownloadManager(telemetry: telemetry),
            unloadModel: { id in
                await gguf.unload(modelID: id)
                await mlx.unload(modelID: id)
            })
        Perf.signposter.endInterval("launch.hub", hubSignpost)
        let reporter = MetricKitReporter(store: diagnostics, telemetry: telemetry)
        reporter.start()
        metricKit = reporter
        telemetry.track(.appOpen)
    }
}
