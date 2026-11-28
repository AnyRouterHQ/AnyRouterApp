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
                Toggle("Show keyboard on launch", isOn: $settings.showKeyboardOnLaunch)
                .accessibilityIdentifier("settings-show-keyboard")
                Picker(selection: $settings.newChatDelay) {
                    ForEach(NewChatDelay.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Start a new chat after")
                }
                .accessibilityIdentifier("settings-new-chat-after")
            } footer: {
                Text("The keyboard opens when you start the app. Leave the app for the time above and it opens on a new chat; a shorter break keeps your conversation.")
            }
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    // It leaves the app for iOS Settings, so it says so like a link.
                    HStack {
                        Text("Paste from Other Apps")
                        Spacer()
                        Image(systemName: "arrow.up.forward").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("settings-paste-permission")
            } footer: {
                Text("Quick actions on something you copied read it when you tap them. Set Paste from Other Apps to Allow so iOS stops asking.")
            }
        }
        .formSwitches()
    }
}
