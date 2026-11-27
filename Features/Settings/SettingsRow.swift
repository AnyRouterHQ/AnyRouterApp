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
                    // Separators start under the title, not under the tile, as in iOS Settings.
                    Text(destination.title).alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                } icon: {
                    SettingsIcon(glyph: destination.glyph, color: destination.tileColor)
                }
            }
        }
    }
}
