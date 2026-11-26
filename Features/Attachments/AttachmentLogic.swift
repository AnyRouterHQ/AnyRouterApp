import Foundation
import UniformTypeIdentifiers

/// Pure rules for attachments: what can be attached, how big, which icon, and what to tell the user.
enum AttachmentLogic {
    static let maxPerMessage = 10
    /// Longest side of a stored image, in pixels.
    static let maxImageSide = 2048
    static let visionNote = "This model cannot see images. The text in them is sent instead."
    static let switchToVisionTitle = "Switch to a vision model"

    /// What the Files importer offers: PDF, text, Markdown, CSV, JSON, source code, XML and images.
    static var importableTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .commaSeparatedText, .json, .sourceCode, .xml, .image]
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        return types
    }

    /// `nil` for a type we cannot read (a zip, a video).
    static func kind(forUTType identifier: String) -> ChatAttachment.Kind? {
        guard let type = UTType(identifier) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) || type.conforms(to: .json) || type.conforms(to: .xml) { return .text }
        return nil
    }

    /// Extensions read as text when the system does not know their type (Markdown on some systems, odd source files).
    static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "xml", "yaml", "yml", "toml", "log", "ini",
        "swift", "py", "js", "ts", "tsx", "jsx", "java", "kt", "c", "h", "cpp", "m", "mm", "go", "rs", "rb", "php",
        "sh", "sql", "html", "css", "tex",
    ]

    /// The kind of a file: by its type first, then by a known text extension.
    static func kind(forUTType identifier: String?, fileExtension: String) -> ChatAttachment.Kind? {
        if let identifier, let kind = kind(forUTType: identifier) { return kind }
        return textExtensions.contains(fileExtension.lowercased()) ? .text : nil
    }

    static func systemImage(for kind: ChatAttachment.Kind) -> String {
        switch kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .audio: "waveform"
        }
    }

    /// "12 KB". Short and locale aware.
    static func sizeText(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    /// Cuts `text` at `AttachmentPrompt.maxCharacters`.
    static func capped(_ text: String) -> (text: String, truncated: Bool) {
        guard text.count > AttachmentPrompt.maxCharacters else { return (text, false) }
        return (String(text.prefix(AttachmentPrompt.maxCharacters)), true)
    }

    /// Size that fits `maxSide` on its longest side, keeping the aspect ratio. Never enlarges.
    static func fittedSize(width: Int, height: Int, maxSide: Int = maxImageSide) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > maxSide, longest > 0 else { return (width, height) }
        let scale = Double(maxSide) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// A name that is safe to show and to use in a path.
    static func displayName(_ name: String, fallback: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleaned.isEmpty ? fallback : cleaned
    }

    static func hasImage(_ attachments: [ChatAttachment]) -> Bool { attachments.contains { $0.kind == .image } }

    /// The note under the composer: pending images and a model that cannot see them.
    static func note(for attachments: [ChatAttachment], model: ModelDescriptor?) -> String? {
        guard hasImage(attachments), let model, !model.supportsVision else { return nil }
        return visionNote
    }

    /// A usable vision model to offer, the current one first when it already sees images.
    static func visionAlternative(in models: [ModelDescriptor]) -> ModelDescriptor? {
        models.first { $0.isInstalled && $0.supportsVision }
    }
}

extension ModelDescriptor {
    /// The model takes images as input.
    var supportsVision: Bool { capabilities.contains("vision") || cloud?.supportsVision == true }
}
