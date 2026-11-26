import Foundation

/// Every page Settings can push. One case plus one view in `SettingsDestinationView` adds a page;
/// other lanes (presets, integrations) fill their view file and leave the list alone.
/// Local Models owns its own sub-pages (Not available, Catalog Sources, Voice): they push from there, not from this list.
enum SettingsDestination: Hashable, CaseIterable, Sendable {
    case localModels, anyRouterModels
    case responseCustomization, presets, integrations
    case theme
    case diagnostics, privacy, terms, licenses

    enum Group: Hashable, CaseIterable, Sendable {
        case models, chat, appearance, about

        var title: String {
            switch self {
            case .models: "Models"
            case .chat: "Chat"
            case .appearance: "Appearance"
            case .about: "About"
            }
        }

        var destinations: [SettingsDestination] {
            switch self {
            case .models: [.localModels, .anyRouterModels]
            case .chat: [.responseCustomization, .presets, .integrations]
            case .appearance: [.theme]
            case .about: [.diagnostics, .privacy, .terms, .licenses]
            }
        }
    }

    var title: String {
        switch self {
        case .localModels: "Local Models"
        case .anyRouterModels: "AnyRouter Models"
        case .responseCustomization: "Response Customization"
        case .presets: "Presets"
        case .integrations: "Integrations"
        case .theme: "Theme"
        case .diagnostics: "Diagnostics"
        case .privacy: "Privacy"
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
        case .theme: "circle.lefthalf.filled"
        case .diagnostics: "waveform.path.ecg"
        case .privacy: "lock"
        case .terms: "doc.text"
        case .licenses: "doc.plaintext"
        }
    }

    /// The group whose section lists this destination.
    var group: Group { Group.allCases.first { $0.destinations.contains(self) } ?? .about }
}
