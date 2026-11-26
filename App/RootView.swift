import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var shell = ShellModel()
    @State private var showsOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AppShell()
            .environment(shell)
            .focusedSceneValue(\.shell, shell)
            .environment(appState.settings)
            .environment(appState.models)
            .tint(ARColor.accent)
            .onChange(of: appState.settings.appearance, initial: true) { _, appearance in
                WindowAppearance.apply(appearance)
            }
            .onChange(of: scenePhase) { _, phase in
                // A scene connected after launch has no override yet.
                if phase == .active { WindowAppearance.apply(appState.settings.appearance) }
            }
            .fullScreenCover(isPresented: $showsOnboarding) {
                OnboardingScreen {
                    appState.settings.hasOnboarded = true
                    showsOnboarding = false
                }
                .environment(appState)
                .environment(appState.models)
                .tint(ARColor.accent)
            }
            .onAppear { showsOnboarding = !appState.settings.hasOnboarded }
            .task {
                await appState.hub.reload()
                await appState.models.refresh()
                // The shared catalog updates without an app release. The bundled list is already showing.
                await appState.hub.refreshCatalog()
            }
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .modelContainer(for: [ThreadRecord.self, MessageRecord.self], inMemory: true)
}
