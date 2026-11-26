import SwiftData
import SwiftUI

@main
struct AnyRouterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer.anyRouter()
        } catch {
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
    }
}
