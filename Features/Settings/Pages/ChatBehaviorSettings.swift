import SwiftUI
import UIKit

/// What the app does when it opens: the keyboard and when a new chat starts.
struct ChatBehaviorSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

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
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Paste from Other Apps", systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("settings-paste-permission")
            } footer: {
                Text("Quick actions on something you copied read it when you tap them. Set Paste from Other Apps to Allow so iOS stops asking.")
            }
        }
    }
}
