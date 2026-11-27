import SwiftUI

/// The colors of the app, in one place. The look is monochrome: one tint (the AccentColor asset, black in light mode
/// and white in dark mode), semantic system colors for everything else, and system colors for the Settings tiles.
/// Do not write `Color(red:)`, `Color(hex)` or `UIColor(red:)` in Features (`scripts/source-check.sh` fails on them).
enum ARPalette {
    /// The one tint, read from the AccentColor asset itself. Not `Color.accentColor`: that one resolves from the UIKit tint
    /// of the hosting window, which turns system blue once a chat shows a photo or file card (quickLookPreview), so
    /// pinning it at the root pinned the blue (the reply-parts thread in screenshots 46014514092).
    static let tint = Color("AccentColor")

    /// Text and symbols on a surface filled with the tint (prominent buttons use `prominentLabel()`).
    static let onTint = Color.accentForeground

    // Meaning, not decoration: use these names so a status looks the same on every screen.
    static let destructive = Color.red
    static let warning = Color.orange
    static let success = Color.green
    static let secondaryText = Color.secondary
}

extension SettingsDestination {
    /// The tile color of the row, like iOS Settings: one system color per page, none close to yellow
    /// (a white symbol on yellow fails contrast).
    var tileColor: Color {
        switch self {
        case .localModels: .green
        case .anyRouterModels: .blue
        case .responseCustomization: .indigo
        case .presets: .orange
        case .integrations: .purple
        case .chatBehavior: .teal
        case .memory: .brown
        case .shortcuts: .pink
        case .theme: .cyan
        case .privacy: .gray
        case .about: .gray
        case .diagnostics: .red
        case .terms: .gray
        case .licenses: .gray
        }
    }
}
