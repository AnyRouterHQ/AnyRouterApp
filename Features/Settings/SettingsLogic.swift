import Foundation

enum SettingsLogic {
    /// Taps on the version row that copy diagnostics.
    static let diagnosticsTapCount = 7

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    static var appBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }

    static var appCommit: String { Bundle.main.infoDictionary?["ARGitCommit"] as? String ?? "dev" }

    /// "0.1.0 (123) · abc1234": the CI run number and commit tell builds apart.
    static func versionText(version: String, build: String, commit: String? = nil) -> String {
        let base = "\(version) (\(build))"
        guard let commit, !commit.isEmpty else { return base }
        return "\(base) · \(commit)"
    }

    /// Plain facts for a bug report. No account, device name or paths.
    static func diagnostics(version: String, build: String, system: String) -> String {
        "AnyRouter \(versionText(version: version, build: build, commit: appCommit))\niOS \(system)"
    }

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
            name: "MarkdownUI",
            copyright: ["Copyright (c) 2020 Guillermo Gonzalez"],
            license: "MIT License",
            url: "https://github.com/gonzalezreal/swift-markdown-ui"
        ),
        LicenseNotice(
            name: "llama.cpp",
            copyright: ["Copyright (c) 2023-2026 The ggml authors"],
            license: "MIT License",
            url: "https://github.com/ggml-org/llama.cpp"
        ),
        LicenseNotice(
            name: "lobe-icons",
            copyright: ["Copyright (c) 2023 LobeHub"],
            license: "MIT License. Logos are trademarks of their owners.",
            url: "https://github.com/lobehub/lobe-icons"
        ),
    ]
}
