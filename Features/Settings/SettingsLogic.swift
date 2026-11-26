import Foundation

enum SettingsLogic {
    /// Accepts `org/name` or a huggingface.co URL and returns `org/name`, or nil when it is not a repo id.
    static func parseRepo(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://huggingface.co/", "http://huggingface.co/", "huggingface.co/"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let owner = String(parts[0]), name = String(parts[1])
        for part in [owner, name] {
            guard !part.isEmpty, part.contains(where: { $0 != "." }), part.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        }
        return "\(owner)/\(name)"
    }
}

/// Third-party licenses shown in Settings (kept in step with THIRD_PARTY_NOTICES.md).
struct LicenseNotice: Identifiable, Equatable {
    var name: String
    var copyright: [String]
    var license: String
    var url: String
    var id: String { name }

    static let all: [LicenseNotice] = [
        LicenseNotice(
            name: "Atomic Chat",
            copyright: ["Copyright 2026 Atomic Chat (https://atomic.chat)", "Copyright 2025 Menlo Research (https://menlo.ai)"],
            license: "Apache License 2.0",
            url: "https://github.com/AtomicBot-ai/Atomic-Chat"
        ),
        LicenseNotice(
            name: "MarkdownUI",
            copyright: ["Copyright (c) 2020 Guillermo Gonzalez"],
            license: "MIT License",
            url: "https://github.com/gonzalezreal/swift-markdown-ui"
        ),
    ]
}
