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
    /// Loads a local model's weights ahead of the first message. Called after launch, never before the first frame.
    let warmUp: @Sendable (ModelDescriptor) async -> Void
    /// Tool servers (AnyRouter MCP and custom ones).
    let integrations: IntegrationsStore
    /// Built-in tools, the AnyRouter MCP server and custom servers, merged for chat and Settings.
    let tools: ToolRegistry
    /// The tool approval sheet's queue.
    let toolApprovals = ToolApprovalCenter()
    /// Typed questions answered by decision models.
    let decisions: DecisionsStore
    /// The one reporting door. Views and engines call this, never a vendor SDK.
    let telemetry: any Telemetry
    /// Saved crash, hang and metric payloads (Settings, Diagnostics).
    let diagnostics = DiagnosticsStore()
    @ObservationIgnored private var metricKit: MetricKitReporter?

    init() {
        // First, so a stall anywhere in launch is recorded (Settings > Diagnostics).
        MainThreadWatchdog.shared.start()
        let tokenStore = KeychainStore()
        // Files that were picked but never sent are not kept across launches.
        if !DemoData.isEnabled { Task.detached { AttachmentStore.shared.purgePending() } }
        let integrations = IntegrationsStore(anyRouterToken: { tokenStore.token() })
        self.integrations = integrations
        tools = ToolRegistry(integrations: integrations)
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
        let telemetry = Diagnostics.makeTelemetry()
        self.telemetry = telemetry
        settings = AppSettings()
        models = ModelStore(registry: registry, telemetry: telemetry, usage: AnyRouterUsageOrder())
        let gguf = GGUFEngine(telemetry: telemetry)
        let mlx = MLXEngine(telemetry: telemetry)
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
        let auth = AnyRouterAuth()
        // Signing in connects the AnyRouter MCP server with the same token; signing out disconnects it.
        auth.onSignedInChange = { [integrations] in _ = integrations.accountChanged(signedIn: $0) }
        if auth.isSignedIn { _ = integrations.accountChanged(signedIn: true) }
        let anyRouter = auth.makeEngine()
        registry.register(anyRouter)
        decisions = DecisionsStore(service: AnyRouterDecisionsAdapter(engine: anyRouter))
        account = AnyRouterAccountAdapter(auth: auth, telemetry: telemetry)
        hub = LocalModelHub(
            downloads: ModelDownloadManager(telemetry: telemetry),
            unloadModel: { id in
                await gguf.unload(modelID: id)
                await mlx.unload(modelID: id)
            })
        let reporter = MetricKitReporter(store: diagnostics, telemetry: telemetry)
        reporter.start()
        metricKit = reporter
        telemetry.track(.appOpen)
    }
}
