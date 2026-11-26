import SwiftData
import SwiftUI

struct RootView: View {
    @State private var shell = ShellModel()

    var body: some View {
        AppShell()
            .environment(shell)
            .tint(ARColor.accent)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [ThreadRecord.self, MessageRecord.self], inMemory: true)
}
