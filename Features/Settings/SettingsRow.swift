import SwiftUI

/// One row that pushes a Settings page: the colored icon tile, the title and an optional second line.
struct SettingsRow: View {
    let destination: SettingsDestination
    let subtitle: String?

    var body: some View {
        NavigationLink(value: destination) {
            LabeledContent {
                if let subtitle { Text(subtitle) }
            } label: {
                Label {
                    Text(destination.title)
                } icon: {
                    SettingsIcon(symbol: destination.systemImage, color: destination.tileColor)
                }
            }
        }
    }
}
