import Foundation

/// Every page Settings can push. One case plus one view in `SettingsDestinationView` adds a page;
/// other lanes (presets, integrations) fill their view file and leave the list alone.
enum SettingsDestination: Hashable, CaseIterable, Sendable {
    case manageModels, defaultModel, inference, catalogSources
    case presets, integrations
    case theme
    case privacy, terms, licenses

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
            case .models: [.manageModels, .defaultModel, .inference, .catalogSources]
            case .chat: [.presets, .integrations]
            case .appearance: [.theme]
            case .about: [.privacy, .terms, .licenses]
            }
        }
    }

    var title: String {
        switch self {
        case .manageModels: "Manage models"
        case .defaultModel: "Default model"
        case .inference: "Inference"
        case .catalogSources: "Catalog sources"
        case .presets: "Presets"
        case .integrations: "Integrations"
        case .theme: "Theme"
        case .privacy: "Privacy"
        case .terms: "Terms"
        case .licenses: "Licenses"
        }
    }

    var systemImage: String {
        switch self {
        case .manageModels: "cube"
        case .defaultModel: "star"
        case .inference: "slider.horizontal.3"
        case .catalogSources: "books.vertical"
        case .presets: "text.badge.star"
        case .integrations: "puzzlepiece.extension"
        case .theme: "circle.lefthalf.filled"
        case .privacy: "lock"
        case .terms: "doc.text"
        case .licenses: "doc.plaintext"
        }
    }

    /// The group whose section lists this destination.
    var group: Group { Group.allCases.first { $0.destinations.contains(self) } ?? .about }
}
