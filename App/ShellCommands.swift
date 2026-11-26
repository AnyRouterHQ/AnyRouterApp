import SwiftUI

/// The focused window's shell, so menu commands act on the window the user is in.
extension FocusedValues {
    @Entry var shell: ShellModel?
}

/// Menu items and keyboard shortcuts for iPad hardware keyboards and the Mac menu bar (Designed for iPad).
struct ShellCommands: Commands {
    @FocusedValue(\.shell) private var shell

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { shell?.newChat(closeSidebar: true) }
                .keyboardShortcut("n")
                .disabled(shell == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find Chats") { shell?.presentSearch() }
                .keyboardShortcut("f")
                .disabled(shell == nil)
        }
        // The View menu's sidebar item, with the standard Mac shortcut (Control Command S).
        CommandGroup(replacing: .sidebar) {
            Button("Toggle Sidebar") { shell?.requestSidebarToggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(shell == nil)
        }
        CommandMenu("Model") {
            Button("Choose Model") { shell?.isModelPickerPresented = true }
                .keyboardShortcut("k")
                .disabled(shell == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { shell?.presentSettings(closeSidebar: false) }
                .keyboardShortcut(",")
                .disabled(shell == nil)
        }
    }
}
