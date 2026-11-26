import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var shell = ShellModel(selectedThreadID: DemoData.initialThreadID)
    @State private var showsOnboarding = false
    /// Set when the chat store could not be opened and was replaced. Shown once.
    @State private var storeNote = StoreOpening.takeNote()
    @Environment(\.scenePhase) private var scenePhase
    /// This window's id for the memory monitor, which unloads only when every window is in the background.
    @State private var sceneID = UUID()
    /// The cold-launch check has run. Until then the first "active" is the launch itself, not a return.
    @State private var launchHandled = false

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
                if phase == .background { appState.settings.lastBackgroundedAt = .now }
                if phase == .active, launchHandled { openNewChatAfterTimeAway() }
                // A scene connected after launch has no override or tap recognizer yet.
                if phase == .active {
                    WindowAppearance.apply(appState.settings.appearance)
                    KeyboardDismissal.install()
                    pickUpShare()
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
            .onAppear {
                showsOnboarding = !appState.settings.hasOnboarded
                pickUpShare()
            }
            // The share extension opens `anyrouter://share` (a share waits in the App Group) or `anyrouter://ask?...`.
            .onOpenURL { url in
                if let request = ShareImportLogic.request(for: url, presets: appState.presets) {
                    InboundChatMailbox.shared.post(request)
                } else {
                    pickUpShare()
                }
            }
            // Siri, Shortcuts and the controls leave a request here; a cold launch has it waiting before the first frame.
            .onChange(of: InboundChatMailbox.shared.pending?.id, initial: true) {
                if let request = InboundChatMailbox.shared.take() { shell.start(request) }
            }
            .alert("Chat history", isPresented: Binding(get: { storeNote != nil }, set: { if !$0 { storeNote = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storeNote ?? "")
            }
            .alert("Help improve AnyRouter?", isPresented: Bindable(appState.settings).isAskingDiagnostics) {
                Button("Share") { appState.settings.answerDiagnostics(share: true) }
                Button("Not now", role: .cancel) { appState.settings.answerDiagnostics(share: false) }
            } message: {
                Text("Share anonymous crash reports and timings. No messages, keys or emails.")
            }
            .task {
                // After the saved chat is restored: a quit and relaunch counts as time away too.
                openNewChatAfterTimeAway()
                launchHandled = true
                if !DemoData.isEnabled {
                    appState.network.start()
                    appState.clipboard.startWatching()
                }
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
    /// Back from the background: after "Start a new chat after" has passed the window opens on an empty chat.
    private func openNewChatAfterTimeAway() {
        let settings = appState.settings
        shell.returned(backgroundedAt: settings.lastBackgroundedAt, now: .now, delay: settings.newChatDelay)
        settings.lastBackgroundedAt = nil
    }

    /// A share the extension left in the App Group opens a fresh chat. Builds without the App Group have no inbox.
    private func pickUpShare() {
        guard !DemoData.isEnabled, let inbox = ShareInbox.appGroup() else { return }
        ShareImportLogic.pickUp(
            inbox: inbox, presets: appState.presets, mailbox: .shared,
            workDirectory: FileManager.default.temporaryDirectory.appending(path: "ShareImport", directoryHint: .isDirectory))
    }

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
