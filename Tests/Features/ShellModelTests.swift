import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct ShellModelTests {
    @Test func newChatClearsSelectionAndClosesSidebarOnlyWhenAsked() {
        let shell = ShellModel()
        shell.select(threadID: UUID(), closeSidebar: false)
        shell.isSidebarOpen = true
        shell.newChat(closeSidebar: false)
        #expect(shell.selectedThreadID == nil)
        #expect(shell.isSidebarOpen)
        shell.newChat(closeSidebar: true)
        #expect(!shell.isSidebarOpen)
    }

    @Test func hubIsASheetAndPickingAThreadDismissesIt() {
        let shell = ShellModel()
        shell.open(.hub, closeSidebar: false)
        #expect(shell.isHubPresented)
        let id = UUID()
        shell.select(threadID: id, closeSidebar: true)
        #expect(!shell.isHubPresented)
        #expect(shell.selectedThreadID == id)
    }

    @Test func decisionsIsASheetThatReplacesTheHubAndIsDismissedByPickingAThread() {
        let shell = ShellModel()
        shell.isSidebarOpen = true
        shell.open(.decisions, closeSidebar: true)
        #expect(shell.isDecisionsPresented && !shell.isHubPresented && !shell.isSidebarOpen)
        shell.open(.hub, closeSidebar: false)
        #expect(shell.isHubPresented && !shell.isDecisionsPresented)
        shell.open(.decisions, closeSidebar: false)
        shell.select(threadID: UUID(), closeSidebar: false)
        #expect(!shell.isDecisionsPresented)
        shell.open(.decisions, closeSidebar: false)
        shell.newChat(closeSidebar: false)
        #expect(!shell.isDecisionsPresented)
    }

    @Test func findCommandPresentsTheSearchScreen() {
        let shell = ShellModel()
        shell.presentSearch()
        #expect(shell.isSearchPresented)
    }

    @Test func openingAThreadFromSearchClosesTheSearchAndTheDrawer() {
        let shell = ShellModel()
        let id = UUID()
        shell.isSidebarOpen = true
        shell.presentSearch()
        shell.openFromSearch(threadID: id)
        #expect(shell.selectedThreadID == id)
        #expect(!shell.isSearchPresented)
        #expect(!shell.isSidebarOpen)
    }

    @Test func settingsIsASheetNotARoute() {
        let shell = ShellModel()
        shell.isSidebarOpen = true
        shell.presentSettings(closeSidebar: true)
        #expect(shell.isSettingsPresented)
        #expect(!shell.isSidebarOpen)
        #expect(!shell.isHubPresented)
    }

    @Test func deletingSelectedThreadResetsSelection() {
        let shell = ShellModel()
        let id = UUID()
        shell.select(threadID: id, closeSidebar: false)
        shell.threadDeleted(UUID())
        #expect(shell.selectedThreadID == id)
        shell.threadDeleted(id)
        #expect(shell.selectedThreadID == nil)
    }
}
