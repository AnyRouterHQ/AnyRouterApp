import Foundation
import Observation

/// Navigation state shared by the shell, sidebar and screens.
@MainActor @Observable
final class ShellModel {
    /// Places the chat can send you. The hub and Decisions are sheets over the chat, not screens of their own.
    enum Route: Hashable, Sendable { case chat, hub, decisions, extract }

    /// `nil` means a new, empty chat. The thread record is created on the first send.
    var selectedThreadID: UUID?
    var isSidebarOpen = false
    /// Settings is a sheet over the shell, not a route.
    var isSettingsPresented = false
    var isHubPresented = false
    var isDecisionsPresented = false
    var isExtractPresented = false
    /// The photo or PDF the composer opened Extract with, taken once by the Extract screen.
    private(set) var extractSeed: ExtractSeed?
    var isModelPickerPresented = false
    /// The full-screen chat search, over the sidebar and the chat.
    var isSearchPresented = false
    /// A reply is streaming in this window. Coming back to the app never takes it off screen.
    var isReplyStreaming = false
    /// The composer takes focus once per launch when the user asked for the keyboard.
    var didFocusComposerOnLaunch = false
    /// Bumped by View > Toggle Sidebar; whichever shell is on screen (drawer or split view) reacts.
    private(set) var sidebarToggleRequest = 0
    /// An outside request (Siri, Shortcuts, a control) waiting for the chat screen to pick it up.
    private(set) var inbound: InboundChat?

    /// The page Settings opens on instead of its list, taken once by `SettingsScreen`.
    var settingsDestination: SettingsDestination?

    func presentSettings(closeSidebar: Bool, destination: SettingsDestination? = nil) {
        settingsDestination = destination
        isSettingsPresented = true
        if closeSidebar { isSidebarOpen = false }
    }

    init(selectedThreadID: UUID? = nil) {
        self.selectedThreadID = selectedThreadID
    }

    func toggleSidebar() { isSidebarOpen.toggle() }

    func requestSidebarToggle() { sidebarToggleRequest += 1 }

    /// The app became active again. After a long enough time away the window opens on a new chat.
    /// Returns true when it did, so the caller can forget the time away.
    @discardableResult
    func returned(backgroundedAt: Date?, now: Date, delay: NewChatDelay) -> Bool {
        let decision = ResumeLogic.decide(backgroundedAt: backgroundedAt, now: now, delay: delay, isStreaming: isReplyStreaming)
        guard decision == .fresh else { return false }
        newChat(closeSidebar: true)
        return true
    }

    /// A cold launch. Keeps the thread already selected, or else reopens `restoring` (the thread this scene showed last),
    /// unless the app was away for the whole delay: then it opens on a new chat, like a return from the background.
    func launched(restoring threadID: UUID?, backgroundedAt: Date?, now: Date, delay: NewChatDelay) {
        let decision = ResumeLogic.decide(backgroundedAt: backgroundedAt, now: now, delay: delay, isStreaming: isReplyStreaming)
        selectedThreadID = decision == .resume ? selectedThreadID ?? threadID : nil
    }

    func newChat(closeSidebar: Bool) {
        selectedThreadID = nil
        isHubPresented = false
        isDecisionsPresented = false
        isExtractPresented = false
        if closeSidebar { isSidebarOpen = false }
    }

    func select(threadID: UUID, closeSidebar: Bool) {
        selectedThreadID = threadID
        isHubPresented = false
        isDecisionsPresented = false
        isExtractPresented = false
        if closeSidebar { isSidebarOpen = false }
    }

    func open(_ route: Route, closeSidebar: Bool) {
        isHubPresented = route == .hub
        isDecisionsPresented = route == .decisions
        isExtractPresented = route == .extract
        if closeSidebar { isSidebarOpen = false }
    }

    func presentSearch() { isSearchPresented = true }

    /// Opens Extract over the chat, on `seed` (the chat's current photo or PDF) when there is one.
    func presentExtract(seed: ExtractSeed?) {
        extractSeed = seed
        open(.extract, closeSidebar: true)
    }

    func takeExtractSeed() -> ExtractSeed? {
        defer { extractSeed = nil }
        return extractSeed
    }

    /// Opens a fresh chat for an outside request, over whatever was open.
    func start(_ request: InboundChat) {
        newChat(closeSidebar: true)
        isSettingsPresented = false
        isSearchPresented = false
        isModelPickerPresented = false
        inbound = request
    }

    func takeInbound() -> InboundChat? {
        defer { inbound = nil }
        return inbound
    }

    /// Opens a thread found in the search, and closes the search and the drawer behind it.
    func openFromSearch(threadID: UUID) {
        select(threadID: threadID, closeSidebar: true)
        isSearchPresented = false
    }

    /// Call after a thread is deleted so the chat screen does not point at it.
    func threadDeleted(_ id: UUID) {
        if selectedThreadID == id { selectedThreadID = nil }
    }
}
