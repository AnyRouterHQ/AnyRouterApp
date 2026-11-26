import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var shell = ShellModel(selectedThreadID: DemoData.initialThreadID)
    @State private var showsOnboarding = false
    @Environment(\.scenePhase) private var scenePhase
    /// This window's id for the memory monitor, which unloads only when every window is in the background.
    @State private var sceneID = UUID()

    var body: some View {
        AppShell()
            .environment(shell)
            .focusedSceneValue(\.shell, shell)
            .environment(appState.settings)
            .environment(appState.models)
            .transformEnvironment(\.horizontalSizeClass) { if let forced = Self.forcedSizeClass { $0 = forced } }
            .onChange(of: appState.settings.appearance, initial: true) { _, appearance in
                WindowAppearance.apply(appearance)
            }
            .onChange(of: scenePhase) { _, phase in
                appState.memory.scene(sceneID, inBackground: phase == .background)
                // A scene connected after launch has no override or tap recognizer yet.
                if phase == .active {
                    WindowAppearance.apply(appState.settings.appearance)
                    KeyboardDismissal.install()
                }
            }
            .onAppear { KeyboardDismissal.install() }
            .onDisappear { appState.memory.sceneClosed(sceneID) }
            .fullScreenCover(isPresented: $showsOnboarding) {
                OnboardingScreen {
                    appState.settings.hasOnboarded = true
                    showsOnboarding = false
                }
                .environment(appState)
                .environment(appState.models)
            }
            .onAppear { showsOnboarding = !appState.settings.hasOnboarded }
            .alert("Help improve AnyRouter?", isPresented: Bindable(appState.settings).isAskingDiagnostics) {
                Button("Share") { appState.settings.answerDiagnostics(share: true) }
                Button("Not now", role: .cancel) { appState.settings.answerDiagnostics(share: false) }
            } message: {
                Text("Share anonymous crash reports and timings. No messages, keys or emails.")
            }
            .task {
                let watchdog = MainThreadWatchdog.shared
                watchdog.mark("launch: local models")
                await appState.hub.reload()
                watchdog.mark("launch: model list")
                await appState.models.refresh()
                // The shared catalog updates without an app release. The bundled list is already showing.
                watchdog.mark("launch: shared catalog")
                await appState.hub.refreshCatalog()
                watchdog.mark("idle")
                await warmSelectedModel()
            }
    }
}

extension RootView {
    /// `-ARSizeClass compact|regular` with demo data: forces the size class. Split View and Slide Over cannot be scripted,
    /// so the UI tests use this to check that a compact iPad window takes the iPhone layout.
    private static var forcedSizeClass: UserInterfaceSizeClass? {
        guard DemoData.isEnabled else { return nil }
        switch UserDefaults.standard.string(forKey: "ARSizeClass") {
        case "compact": return .compact
        case "regular": return .regular
        default: return nil
        }
    }

    /// After the first frame: load the chosen local model in the background, but only one that runs well here, so a
    /// model that is too big for the device is never loaded just to be ready.
    private func warmSelectedModel() async {
        guard let model = appState.models.selected, model.source == .gguf,
              appState.hub.catalog.first(where: { $0.id == model.id })?.fitDetail?.verdict == .fits
        else { return }
        let warm = appState.warmUp
        await Task.detached(priority: .utility) { await warm(model) }.value
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .modelContainer(for: [ThreadRecord.self, MessageRecord.self], inMemory: true)
}
