import SwiftUI

/// The typeface of reply text. Code stays monospaced in every one.
enum ReplyFont: String, CaseIterable, Identifiable, Sendable {
    case system, serif, rounded

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        }
    }
}

/// The size setting for reply text: whole steps around the system size, so Dynamic Type still applies on top.
enum ReplyText {
    static let steps = -2...3
    static let defaultStep = 0
    /// Each step is this much of the system size.
    static let stepSize = 0.06

    static func clamped(_ step: Int) -> Int { min(max(step, steps.lowerBound), steps.upperBound) }

    static func scale(step: Int) -> Double { 1 + stepSize * Double(clamped(step)) }

    /// The body size of a reply in points, from the size Dynamic Type gives the body style.
    static func points(_ base: CGFloat, step: Int) -> CGFloat { (base * scale(step: step)).rounded() }

    /// "Default", "-2", "+3".
    static func label(step: Int) -> String {
        let value = clamped(step)
        if value == defaultStep { return "Default" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    /// What VoiceOver reads for the live preview in Settings.
    static func previewLabel(step: Int, font: ReplyFont) -> String {
        "Preview of a reply, text size \(label(step: step).lowercased()), \(font.title.lowercased()) font"
    }
}
