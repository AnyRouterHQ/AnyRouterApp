import Foundation
import Observation

/// Navigation state shared by the shell, sidebar and screens.
@MainActor @Observable
final class ShellModel {
    /// Places the chat can send you. The hub is a sheet over the chat, not a screen of its own.
    enum Route: Hashable, Sendable { case chat, hub }

    /// `nil` means a new, empty chat. The thread record is created on the first send.
    var selectedThreadID: UUID?
    var isSidebarOpen = false
    /// Settings is a sheet over the shell, not a route.
    var isSettingsPresented = false
    var isHubPresented = false
    var isModelPickerPresented = false
    /// Bumped by the Find command; the sidebar reacts by opening its search field.
    private(set) var searchRequest = 0
    /// The composer takes focus once per launch when the user asked for the keyboard.
    var didFocusComposerOnLaunch = false

    func presentSettings(closeSidebar: Bool) {
        isSettingsPresented = true
        if closeSidebar { isSidebarOpen = false }
    }

    func toggleSidebar() { isSidebarOpen.toggle() }

    func newChat(closeSidebar: Bool) {
        selectedThreadID = nil
        isHubPresented = false
        if closeSidebar { isSidebarOpen = false }
    }

    func select(threadID: UUID, closeSidebar: Bool) {
        selectedThreadID = threadID
        isHubPresented = false
        if closeSidebar { isSidebarOpen = false }
    }

    func open(_ route: Route, closeSidebar: Bool) {
        isHubPresented = route == .hub
        if closeSidebar { isSidebarOpen = false }
    }

    func requestSidebarSearch() {
        isSidebarOpen = true
        searchRequest += 1
    }

    /// Call after a thread is deleted so the chat screen does not point at it.
    func threadDeleted(_ id: UUID) {
        if selectedThreadID == id { selectedThreadID = nil }
    }
}
