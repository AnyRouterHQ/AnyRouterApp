import SwiftUI

/// What the app does when it opens: the keyboard and when a new chat starts.
struct ChatBehaviorSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle(isOn: $settings.showKeyboardOnLaunch) {
                    Label("Show keyboard on launch", systemImage: "keyboard")
                }
                .accessibilityIdentifier("settings-show-keyboard")
                Picker(selection: $settings.newChatDelay) {
                    ForEach(NewChatDelay.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Start a new chat after", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("settings-new-chat-after")
            } footer: {
                Text("The keyboard opens when you start the app. Leave the app for the time above and it opens on a new chat; a shorter break keeps your conversation.")
            }
        }
    }
}
