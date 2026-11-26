import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var shell = ShellModel()
    @State private var showsOnboarding = false

    var body: some View {
        AppShell()
            .environment(shell)
            .focusedSceneValue(\.shell, shell)
            .environment(appState.settings)
            .environment(appState.models)
            .tint(ARColor.accent)
            .preferredColorScheme(appState.settings.appearance.colorScheme)
            .fullScreenCover(isPresented: $showsOnboarding) {
                OnboardingScreen {
                    appState.settings.hasOnboarded = true
                    showsOnboarding = false
                }
                .environment(appState)
                .environment(appState.models)
                .tint(ARColor.accent)
                .preferredColorScheme(appState.settings.appearance.colorScheme)
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
