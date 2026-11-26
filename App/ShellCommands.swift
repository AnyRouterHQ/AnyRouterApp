import SwiftUI

/// The focused window's shell, so menu commands act on the window the user is in.
extension FocusedValues {
    @Entry var shell: ShellModel?
}

/// Keyboard shortcuts for iPad and hardware keyboards.
struct ShellCommands: Commands {
    @FocusedValue(\.shell) private var shell

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") { shell?.newChat(closeSidebar: true) }
                .keyboardShortcut("n")
                .disabled(shell == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find Chats") { shell?.requestSidebarSearch() }
                .keyboardShortcut("f")
                .disabled(shell == nil)
        }
        CommandMenu("Model") {
            Button("Choose Model") { shell?.isModelPickerPresented = true }
                .keyboardShortcut("k")
                .disabled(shell == nil)
        }
        CommandGroup(after: .appSettings) {
            Button("Settings…") { shell?.presentSettings(closeSidebar: false) }
                .keyboardShortcut(",")
                .disabled(shell == nil)
        }
    }
}
