import Foundation
import Observation
import SwiftUI
import UIKit

/// User preferences backed by `UserDefaults`. Generation defaults feed every chat request.
@MainActor @Observable
final class AppSettings {
    enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var userInterfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .system: .unspecified
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
        static let shareDiagnostics = "settings.shareDiagnostics"
        static let diagnosticsAsked = "settings.diagnosticsAsked"
        static let showResponseDetails = "settings.showResponseDetails"
        static let replyTextStep = "settings.replyTextStep"
        static let replyFont = "settings.replyFont"
        static let newChatDelay = "settings.newChatDelay"
        static let backgroundedAt = "settings.backgroundedAt"
    }

    /// The key behind `onDeviceTools`, so an engine can read the switch without the main actor.
    nonisolated static let onDeviceToolsKey = "settings.onDeviceTools"

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Tools for models that run on this device (llama.cpp and MLX). On until the person turns it off; such a model is
    /// offered four tools at most (`ToolProfile.compact`), so the list fits its small context.
    var onDeviceTools: Bool {
        get { access(keyPath: \.onDeviceTools); return Self.onDeviceToolsOn(defaults: defaults) }
        set { withMutation(keyPath: \.onDeviceTools) { defaults.set(newValue, forKey: Self.onDeviceToolsKey) } }
    }

    /// The same switch without an instance, for the engines that run off the main actor.
    nonisolated static func onDeviceToolsOn(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: onDeviceToolsKey) as? Bool ?? true
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

    /// True while the one-time "Help improve AnyRouter?" alert should show. Not stored: it is set after the first good chat.
    var isAskingDiagnostics = false

    /// Whether the question was already answered (either way). It is asked once.
    var diagnosticsAsked: Bool {
        get { access(keyPath: \.diagnosticsAsked); return defaults.bool(forKey: Key.diagnosticsAsked) }
        set { withMutation(keyPath: \.diagnosticsAsked) { defaults.set(newValue, forKey: Key.diagnosticsAsked) } }
    }

    /// Called after a chat reply came back. Raises the question once, in a build that has a DSN.
    func noteSuccessfulChat(configured: Bool = Diagnostics.isConfigured) {
        if DiagnosticsConfig.shouldAskToShare(configured: configured, asked: diagnosticsAsked) {
            isAskingDiagnostics = true
        }
    }

    /// The alert's two buttons. Both remember the answer, so the question is not asked again.
    func answerDiagnostics(share: Bool) {
        shareDiagnostics = share
        diagnosticsAsked = true
        isAskingDiagnostics = false
    }

    /// "Share anonymous diagnostics". Off until the user says yes, even when this build has a Sentry DSN.
    var shareDiagnostics: Bool {
        get { access(keyPath: \.shareDiagnostics); return Self.sharesDiagnostics(defaults: defaults) }
        set { withMutation(keyPath: \.shareDiagnostics) { defaults.set(newValue, forKey: Key.shareDiagnostics) } }
    }

    /// The same answer without an instance, for code that runs off the main actor (the telemetry gate).
    nonisolated static func sharesDiagnostics(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.shareDiagnostics) as? Bool ?? false
    }

    var showKeyboardOnLaunch: Bool {
        get { access(keyPath: \.showKeyboardOnLaunch); return defaults.bool(forKey: Key.showKeyboard) }
        set { withMutation(keyPath: \.showKeyboardOnLaunch) { defaults.set(newValue, forKey: Key.showKeyboard) } }
    }

    /// Model, cost and speed under each reply. On by default.
    var showResponseDetails: Bool {
        get { access(keyPath: \.showResponseDetails); return defaults.object(forKey: Key.showResponseDetails) as? Bool ?? true }
        set { withMutation(keyPath: \.showResponseDetails) { defaults.set(newValue, forKey: Key.showResponseDetails) } }
    }

    /// Reply text size, in steps around the system size (`ReplyText.steps`). 0 is the system size.
    var replyTextStep: Int {
        get { access(keyPath: \.replyTextStep); return ReplyText.clamped(defaults.integer(forKey: Key.replyTextStep)) }
        set { withMutation(keyPath: \.replyTextStep) { defaults.set(ReplyText.clamped(newValue), forKey: Key.replyTextStep) } }
    }

    /// Typeface of reply text.
    var replyFont: ReplyFont {
        get {
            access(keyPath: \.replyFont)
            return defaults.string(forKey: Key.replyFont).flatMap(ReplyFont.init(rawValue:)) ?? .system
        }
        set { withMutation(keyPath: \.replyFont) { defaults.set(newValue.rawValue, forKey: Key.replyFont) } }
    }

    /// How long the app can stay in the background before it opens on a new chat. One minute by default.
    var newChatDelay: NewChatDelay {
        get {
            access(keyPath: \.newChatDelay)
            return defaults.string(forKey: Key.newChatDelay).flatMap(NewChatDelay.init(rawValue:)) ?? .standard
        }
        set { withMutation(keyPath: \.newChatDelay) { defaults.set(newValue.rawValue, forKey: Key.newChatDelay) } }
    }

    /// When the app last went to the background. Kept on disk so a quit and relaunch counts as time away too.
    var lastBackgroundedAt: Date? {
        get { access(keyPath: \.lastBackgroundedAt); return defaults.object(forKey: Key.backgroundedAt) as? Date }
        set { withMutation(keyPath: \.lastBackgroundedAt) { defaults.set(newValue, forKey: Key.backgroundedAt) } }
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
