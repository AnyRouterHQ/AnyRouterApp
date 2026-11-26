import Foundation

/// A row of the @ list: a plugin (a tool source) or a file of this chat.
struct MentionItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case plugin(sourceID: String)
        case file(attachmentID: UUID, filename: String)
        /// A preset with pickers (Reply to this). It opens its choices instead of becoming a chip.
        case preset(presetID: String)
    }

    var kind: Kind
    var title: String
    /// Grey text at the end of the row.
    var trailing: String
    var icon: ToolSource.Icon

    var id: String {
        switch kind {
        case .plugin(let sourceID): "plugin/\(sourceID)"
        case .file(let attachmentID, _): "file/\(attachmentID.uuidString)"
        case .preset(let presetID): "preset/\(presetID)"
        }
    }

    /// The source this mention turns on for the next message. A file is read by an on-device tool. A preset turns none on.
    var forcedSourceID: String? {
        switch kind {
        case .plugin(let sourceID): sourceID
        case .file: ToolSourceCatalog.device.id
        case .preset: nil
        }
    }
}

/// The @ list above the composer: what the words after an @ ask for, which rows match, and what a choice does.
/// Pure, so it is tested without a view.
enum ComposerMention {
    static let prompt = "Type to search plugins, presets and files"
    static let pluginLabel = "Plugin"
    static let presetLabel = "Preset"
    static let fileLabel = "File"
    /// The files the list offers at most.
    static let maxFiles = 8

    /// The words typed after an @ that ends the text and starts a word (not the @ of an address).
    /// Nil when the text has no such @ or a space ended the word.
    static func query(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        if at != text.startIndex, !text[text.index(before: at)].isWhitespace { return nil }
        let rest = text[text.index(after: at)...]
        guard !rest.contains(where: \.isWhitespace) else { return nil }
        return String(rest)
    }

    /// Plugins first, then presets with pickers, then the newest files.
    static func items(sources: [ToolSource], files: [ChatAttachment], presets: [PromptPreset] = []) -> [MentionItem] {
        let plugins = sources.map {
            MentionItem(kind: .plugin(sourceID: $0.id), title: $0.title, trailing: pluginLabel, icon: $0.icon)
        }
        let helpers = presets.filter(\.hasOptions).map {
            MentionItem(kind: .preset(presetID: $0.id), title: $0.title, trailing: presetLabel, icon: .symbol($0.symbol))
        }
        let recent = files.suffix(maxFiles).reversed().map {
            MentionItem(
                kind: .file(attachmentID: $0.id, filename: $0.filename), title: $0.filename, trailing: fileLabel,
                icon: .symbol(symbol(for: $0.kind)))
        }
        return plugins + helpers + recent
    }

    private static func symbol(for kind: ChatAttachment.Kind) -> String {
        switch kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .audio: "waveform"
        }
    }

    /// Rows whose name has a word starting with the query come first, then rows that contain it. Case and accents do not matter.
    static func filter(_ items: [MentionItem], query: String) -> [MentionItem] {
        let wanted = fold(query)
        guard !wanted.isEmpty else { return items }
        var starts: [MentionItem] = []
        var contains: [MentionItem] = []
        for item in items {
            let title = fold(item.title)
            if title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(wanted) }) {
                starts.append(item)
            } else if title.contains(wanted) {
                contains.append(item)
            }
        }
        return starts + contains
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }

    /// The text without the "@words" being typed, and without the space in front of it.
    static func removingQuery(from text: String) -> String {
        guard query(in: text) != nil, let at = text.lastIndex(of: "@") else { return text }
        return String(text[..<at]).trimmingCharacters(in: .whitespaces)
    }

    static func forcedSourceIDs(of mentions: [MentionItem]) -> Set<String> {
        Set(mentions.compactMap(\.forcedSourceID))
    }

    /// One sentence that tells the model what the user asked for.
    static func hint(for mentions: [MentionItem]) -> String? {
        let plugins = mentions.compactMap { item -> String? in
            if case .plugin = item.kind { return item.title }
            return nil
        }
        let files = mentions.compactMap { item -> String? in
            if case .file(_, let name) = item.kind { return name }
            return nil
        }
        var sentences: [String] = []
        if !plugins.isEmpty { sentences.append("Use the tools of \(plugins.joined(separator: " and ")) to answer this message.") }
        let quoted = files.map { "\"" + $0 + "\"" }.joined(separator: " and ")
        if !files.isEmpty { sentences.append("Read " + quoted + " with the read_attachment tool first.") }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// The history for one request, with the hint after the last message of the user. The saved chat is not changed.
    static func applying(_ mentions: [MentionItem], to messages: [ChatMessage]) -> [ChatMessage] {
        guard let hint = hint(for: mentions), let index = messages.lastIndex(where: { $0.role == .user }) else { return messages }
        var copy = messages
        copy[index].content += "\n\n" + hint
        return copy
    }
}
