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
    /// It looks again whenever `activity` changes (a reply starts, its model finishes loading, a reply ends: the
    /// moments a model may have been loaded) and, only while a model is in memory, every 10 seconds. With nothing
    /// loaded there is no loop, so an idle home screen does no work.
    func refreshesMemory(_ monitor: MemoryMonitor, activity: Int) -> some View {
        task(id: activity) {
            await monitor.refresh()
            while monitor.loadedModelID != nil, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await monitor.refresh()
            }
        }
    }
}
