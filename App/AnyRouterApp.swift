import SwiftData
import SwiftUI

@main
struct AnyRouterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared
    private let container: ModelContainer

    init() {
        let signpost = Perf.signposter.beginInterval("launch.container")
        defer { Perf.signposter.endInterval("launch.container", signpost) }
        do {
            if DemoData.isEnabled {
                container = try DemoData.makeContainer()
            } else {
                let outcome = try StoreOpening.open()
                container = outcome.container
                StoreOpening.post(note: outcome.note)
            }
        } catch {
            // Only an in-memory container failing lands here, which no data on disk can cause.
            fatalError("Could not create the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(appState.registry)
        }
        .modelContainer(container)
        .commands { ShellCommands() }
    }
}
