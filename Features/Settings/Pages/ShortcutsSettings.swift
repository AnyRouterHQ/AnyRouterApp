import AppIntents
import SwiftUI

/// Settings › Shortcuts & Controls: the system Siri tip and Shortcuts button, the phrases Siri knows, then each way to
/// reach AnyRouter from outside the app with how to add it.
struct ShortcutsSettings: View {
    @State private var showsSiriTip = true

    var body: some View {
        List {
            Section {
                SiriTipView(intent: AskAnyRouterIntent(), isVisible: $showsSiriTip)
                ShortcutsLink()
            }
            Section {
                ForEach(ShortcutsLogic.siriPhrases) { phrase in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(phrase.phrase)”")
                        Text(phrase.action).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Say to Siri")
            } footer: {
                Text("These also show in Spotlight and in the Shortcuts app.")
            }
            ForEach(ShortcutsLogic.features) { feature in
                Section {
                    Label(feature.summary, systemImage: feature.symbol)
                } header: {
                    Text(feature.title)
                } footer: {
                    Text("How to add: \(feature.howToAdd)")
                }
            }
        }
        .accessibilityIdentifier("settings-shortcuts")
    }
}
