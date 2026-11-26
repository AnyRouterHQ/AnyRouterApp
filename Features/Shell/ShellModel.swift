import Foundation
import Observation

/// Navigation state shared by the shell, sidebar and screens.
@MainActor @Observable
final class ShellModel {
    enum Route: Hashable, Sendable { case chat, hub }

    var route: Route = .chat
    /// `nil` means a new, empty chat. The thread record is created on the first send.
    var selectedThreadID: UUID?
    var isSidebarOpen = false
    /// Settings is a sheet over the shell, not a route.
    var isSettingsPresented = false
    /// The composer takes focus once per launch when the user asked for the keyboard.
    var didFocusComposerOnLaunch = false

    func presentSettings(closeSidebar: Bool) {
        isSettingsPresented = true
        if closeSidebar { isSidebarOpen = false }
    }

    func toggleSidebar() { isSidebarOpen.toggle() }

    func newChat(closeSidebar: Bool) {
        selectedThreadID = nil
        route = .chat
        if closeSidebar { isSidebarOpen = false }
    }

    func select(threadID: UUID, closeSidebar: Bool) {
        selectedThreadID = threadID
        route = .chat
        if closeSidebar { isSidebarOpen = false }
    }

    func open(_ route: Route, closeSidebar: Bool) {
        self.route = route
        if closeSidebar { isSidebarOpen = false }
    }

    /// Call after a thread is deleted so the chat screen does not point at it.
    func threadDeleted(_ id: UUID) {
        if selectedThreadID == id { selectedThreadID = nil }
    }
}
