import AppIntents
import SwiftUI

/// Settings › Shortcuts & Controls: each way to reach AnyRouter from outside the app, with how to add it.
struct ShortcutsSettings: View {
    var body: some View {
        List {
            ForEach(ShortcutsLogic.features) { feature in
                Section {
                    Label(feature.summary, systemImage: feature.symbol)
                } header: {
                    Text(feature.title)
                } footer: {
                    Text("How to add: \(feature.howToAdd)")
                }
            }
            Section {
                ShortcutsLink()
            } footer: {
                Text("Opens the AnyRouter actions in the Shortcuts app.")
            }
        }
        .accessibilityIdentifier("settings-shortcuts")
    }
}
