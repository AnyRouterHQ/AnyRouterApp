import SwiftUI

/// Small indicator in the chat header while a local model is in memory: what it is, what the app uses, and unload.
struct MemoryMenu: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    private var monitor: MemoryMonitor { app.memory }
    private var loadedName: String? {
        monitor.loadedModelID.map { id in models.models.first { $0.id == id }?.displayName ?? "Local model" }
    }
    /// Under 1 GB left: the system may end the app soon.
    private var isLow: Bool { monitor.readout.availableBytes > 0 && monitor.readout.availableBytes < 1_000_000_000 }

    var body: some View {
        Group {
            if let loadedName {
                Menu {
                    Text(loadedName)
                    Text(FitText.memoryLine(
                        footprintBytes: monitor.readout.footprintBytes, availableBytes: monitor.readout.availableBytes))
                    Divider()
                    Button("Unload model", role: .destructive) { Task { await monitor.unload() } }
                } label: {
                    Image(systemName: "memorychip")
                        .foregroundStyle(isLow ? Color.red : Color.primary)
                }
                .accessibilityLabel("Model memory")
                .accessibilityIdentifier("memory-menu")
            }
        }
        .task {
            while !Task.isCancelled {
                await monitor.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
