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

    @Test func selectingThreadReturnsToChatRoute() {
        let shell = ShellModel()
        shell.open(.hub, closeSidebar: false)
        let id = UUID()
        shell.select(threadID: id, closeSidebar: true)
        #expect(shell.route == .chat)
        #expect(shell.selectedThreadID == id)
    }

    @Test func settingsIsASheetNotARoute() {
        let shell = ShellModel()
        shell.isSidebarOpen = true
        shell.presentSettings(closeSidebar: true)
        #expect(shell.isSettingsPresented)
        #expect(!shell.isSidebarOpen)
        #expect(shell.route == .chat)
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
