import Foundation

/// Every page Settings can push. One case plus one view in `SettingsDestinationView` adds a page;
/// other lanes (presets, integrations) fill their view file and leave the list alone.
/// Local Models owns its own sub-pages (Not available, Catalog Sources, Voice): they push from there, not from this list.
/// About owns Diagnostics, Terms and Licenses (`aboutPages`): they push from the About page, not from the root.
enum SettingsDestination: Hashable, CaseIterable, Sendable {
    case localModels, anyRouterModels
    case responseCustomization, presets, integrations, chatBehavior
    case shortcuts, theme, privacy, about
    case diagnostics, terms, licenses

    /// The sections of the root list below the account card, in order.
    enum Group: Hashable, CaseIterable, Sendable {
        case models, chat, app

        var title: String {
            switch self {
            case .models: "Models"
            case .chat: "Chat"
            case .app: "App"
            }
        }

        var destinations: [SettingsDestination] {
            switch self {
            case .models: [.localModels, .anyRouterModels]
            case .chat: [.responseCustomization, .presets, .integrations, .chatBehavior]
            case .app: [.shortcuts, .theme, .privacy, .about]
            }
        }
    }

    /// The rows of the About page, under the version.
    static let aboutPages: [SettingsDestination] = [.diagnostics, .terms, .licenses]

    var title: String {
        switch self {
        case .localModels: "Local Models"
        case .anyRouterModels: "AnyRouter Models"
        case .responseCustomization: "Responses"
        case .presets: "Presets"
        case .integrations: "Integrations"
        case .chatBehavior: "Chat Behavior"
        case .shortcuts: "Shortcuts & Controls"
        case .theme: "Theme"
        case .privacy: "Privacy"
        case .about: "About"
        case .diagnostics: "Diagnostics"
        case .terms: "Terms"
        case .licenses: "Licenses"
        }
    }

    var systemImage: String {
        switch self {
        case .localModels: "cube"
        case .anyRouterModels: "cloud"
        case .responseCustomization: "slider.horizontal.3"
        case .presets: "text.badge.star"
        case .integrations: "puzzlepiece.extension"
        case .chatBehavior: "bubble.left.and.text.bubble.right"
        case .shortcuts: "square.stack.3d.up"
        case .theme: "circle.lefthalf.filled"
        case .privacy: "lock"
        case .about: "info.circle"
        case .diagnostics: "waveform.path.ecg"
        case .terms: "doc.text"
        case .licenses: "doc.plaintext"
        }
    }

    /// The tile glyph: the page's symbol, except AnyRouter Models, which shows the AnyRouter mark.
    var glyph: SettingsIcon.Glyph {
        self == .anyRouterModels ? .asset(ModelBrand.anyRouterMark) : .symbol(systemImage)
    }

    /// The root section that lists this destination, or nil for a page that opens from another page.
    var group: Group? { Group.allCases.first { $0.destinations.contains(self) } }
}
