import Foundation

/// Text read from a photo or a scan, waiting in a sheet until the user picks what to do with it.
struct ScannedText: Identifiable, Equatable, Sendable {
    let id = UUID()
    var text: String
}

enum OCRLogic {
    /// Vision's own name for Vietnamese is "vi-VT" (it is what `supportedRecognitionLanguages()` lists). "vi-VN" is the
    /// standard code, kept in case a later system uses it. Vision drops a code it does not know without saying so.
    static let vietnameseCodes = ["vi-VT", "vi-VN"]
    static let englishCodes = ["en-US"]

    /// The ids of the presets offered after a scan, in the order the sheet lists them.
    static let scanPresetIDs = ["translate", "split-bill", "summarize"]

    static let noTextMessage = "No text found in the photo."

    /// Vietnamese (first, since its model is not the default), then English, each as Vision names it on this system.
    /// A language Vision does not list is left out; empty means "use Vision's default".
    static func languages(supported: [String]) -> [String] {
        let vietnamese = vietnameseCodes.first(where: supported.contains).map { [$0] } ?? []
        return vietnamese + englishCodes.filter { supported.contains($0) }
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
