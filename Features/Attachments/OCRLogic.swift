import Foundation

/// Text read from a photo or a scan, waiting in a sheet until the user picks what to do with it.
struct ScannedText: Identifiable, Equatable, Sendable {
    let id = UUID()
    var text: String
}

enum OCRLogic {
    /// Vision's names for the languages the app reads. Vietnamese comes first because it is not the default model.
    static let preferredLanguages = ["vi-VT", "en-US"]

    /// The ids of the presets offered after a scan, in the order the sheet lists them.
    static let scanPresetIDs = ["translate", "split-bill", "summarize"]

    static let noTextMessage = "No text found in the photo."

    /// The preferred languages this device's Vision supports, in priority order. Empty means "use Vision's default".
    static func languages(supported: [String]) -> [String] {
        preferredLanguages.filter { supported.contains($0) }
    }

    /// Several photos: one block each, with a blank line between.
    static func join(_ texts: [String]) -> String {
        texts.joined(separator: "\n\n")
    }

    /// The scan goes under what the user already typed.
    static func appended(_ scan: String, to input: String) -> String {
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? scan : typed + "\n\n" + scan
    }
}
