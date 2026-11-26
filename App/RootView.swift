import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var shell = ShellModel()

    var body: some View {
        AppShell()
            .environment(shell)
            .environment(appState.settings)
            .environment(appState.models)
            .tint(ARColor.accent)
            .preferredColorScheme(appState.settings.appearance.colorScheme)
            .task { await appState.models.refresh() }
    }
}

#Preview {
    RootView()
        .environment(AppState())
        .modelContainer(for: [ThreadRecord.self, MessageRecord.self], inMemory: true)
}
