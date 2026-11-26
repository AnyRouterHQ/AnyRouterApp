import SwiftUI

/// While a local model is in memory, a submenu of the composer's plus menu: what it is, what the app uses, and unload.
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
        if let loadedName {
            Menu {
                Text(loadedName)
                Text(FitText.memoryLine(
                    footprintBytes: monitor.readout.footprintBytes, availableBytes: monitor.readout.availableBytes))
                Divider()
                Button("Unload model", role: .destructive) { Task { await monitor.unload() } }
            } label: {
                Label(isLow ? "Model memory, low" : "Model memory", systemImage: "memorychip")
            }
            .accessibilityIdentifier("memory-menu")
        }
    }
}

extension View {
    /// Keeps the memory readout fresh while this view is on screen. The menu above only reads it.
    func refreshesMemory(_ monitor: MemoryMonitor) -> some View {
        task {
            while !Task.isCancelled {
                await monitor.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
