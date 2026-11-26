import Foundation
import Observation
import SwiftUI

/// User preferences backed by `UserDefaults`. Generation defaults feed every chat request.
@MainActor @Observable
final class AppSettings {
    enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    private enum Key {
        static let temperature = "settings.temperature"
        static let topP = "settings.topP"
        static let maxTokens = "settings.maxTokens"
        static let systemPrompt = "settings.systemPrompt"
        static let appearance = "settings.appearance"
        static let onboarded = "settings.onboarded"
        static let showKeyboard = "settings.showKeyboardOnLaunch"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var temperature: Double {
        get { access(keyPath: \.temperature); return defaults.object(forKey: Key.temperature) as? Double ?? 0.7 }
        set { withMutation(keyPath: \.temperature) { defaults.set(newValue, forKey: Key.temperature) } }
    }

    var topP: Double {
        get { access(keyPath: \.topP); return defaults.object(forKey: Key.topP) as? Double ?? 0.95 }
        set { withMutation(keyPath: \.topP) { defaults.set(newValue, forKey: Key.topP) } }
    }

    /// 0 means no limit.
    var maxTokens: Int {
        get { access(keyPath: \.maxTokens); return defaults.integer(forKey: Key.maxTokens) }
        set { withMutation(keyPath: \.maxTokens) { defaults.set(newValue, forKey: Key.maxTokens) } }
    }

    var systemPrompt: String {
        get { access(keyPath: \.systemPrompt); return defaults.string(forKey: Key.systemPrompt) ?? "" }
        set { withMutation(keyPath: \.systemPrompt) { defaults.set(newValue, forKey: Key.systemPrompt) } }
    }

    var appearance: Appearance {
        get {
            access(keyPath: \.appearance)
            return defaults.string(forKey: Key.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        }
        set { withMutation(keyPath: \.appearance) { defaults.set(newValue.rawValue, forKey: Key.appearance) } }
    }

    var hasOnboarded: Bool {
        get { access(keyPath: \.hasOnboarded); return defaults.bool(forKey: Key.onboarded) }
        set { withMutation(keyPath: \.hasOnboarded) { defaults.set(newValue, forKey: Key.onboarded) } }
    }

    var showKeyboardOnLaunch: Bool {
        get { access(keyPath: \.showKeyboardOnLaunch); return defaults.bool(forKey: Key.showKeyboard) }
        set { withMutation(keyPath: \.showKeyboardOnLaunch) { defaults.set(newValue, forKey: Key.showKeyboard) } }
    }

    var generationParams: GenerationParams {
        let prompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return GenerationParams(
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens > 0 ? maxTokens : nil,
            systemPrompt: prompt.isEmpty ? nil : prompt
        )
    }

    func resetGenerationDefaults() {
        temperature = 0.7
        topP = 0.95
        maxTokens = 0
        systemPrompt = ""
    }
}
