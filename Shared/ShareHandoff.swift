import Foundation

// Compiled into the app and the share extension. The extension saves what was shared; the app picks it up.

/// What the person wants done with a shared item. Each one maps to a built-in preset the app resolves by id.
enum ShareAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case ask, summarize, translate, fixEnglish, reply

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .summarize: "Summarize"
        case .translate: "Translate"
        case .fixEnglish: "Fix my English"
        case .reply: "Reply to this"
        }
    }

    var presetID: String? {
        switch self {
        case .ask: nil
        case .summarize: "summarize"
        case .translate: "translate"
        case .fixEnglish: InboundPreset.fixEnglish
        case .reply: "reply-to-this"
        }
    }
}

struct SharedFile: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case image, pdf }

    var filename: String
    var kind: Kind
}

/// One share, as the extension saves it: text, a link, files and the chosen action.
struct SharedPayload: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var createdAt = Date()
    var text: String?
    var url: String?
    var files: [SharedFile] = []
    var action = ShareAction.ask
}

/// The folder in the shared App Group container where shares wait for the app. One folder per share, with
/// `payload.json` and the files next to it.
struct ShareInbox: Sendable {
    static let groupID = "group.oneni.anyr.app"
    private static let payloadName = "payload.json"

    let root: URL

    /// `nil` when this build has no App Group: a build signed without the capability, such as a sideload through a
    /// signing tool that drops entitlements. Callers then use `ShareDeepLink` or say so.
    static func appGroup(fileManager: FileManager = .default) -> ShareInbox? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        return ShareInbox(root: container.appending(path: "ShareInbox", directoryHint: .isDirectory))
    }

    func folder(for id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// Creates the folder for a share. Copy its files in, then `save`.
    func prepare(_ id: UUID) throws -> URL {
        let folder = folder(for: id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Written last, so the app never sees a share whose files are still being copied.
    func save(_ payload: SharedPayload) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(payload).write(to: folder(for: payload.id).appending(path: Self.payloadName), options: .atomic)
    }

    /// Complete shares, oldest first. A folder without a readable `payload.json` is still being written, or is damaged: skipped.
    func pending() -> [SharedPayload] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders
            .compactMap { try? Data(contentsOf: $0.appending(path: Self.payloadName)) }
            .compactMap { try? decoder.decode(SharedPayload.self, from: $0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func discard(_ payload: SharedPayload) {
        try? FileManager.default.removeItem(at: folder(for: payload.id))
    }

    /// Moves a share's folder out of the group container into `destination`, so the files outlive the inbox entry.
    /// Returns the folder that now holds them.
    func claim(_ payload: SharedPayload, into destination: URL) throws -> URL {
        let target = destination.appending(path: payload.id.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: folder(for: payload.id), to: target)
        return target
    }
}

/// The links between the extension and the app. `anyrouter://share` says "a share is waiting in the inbox".
/// `anyrouter://ask?text=&action=` carries a short text itself, for builds that have no App Group.
enum ShareDeepLink {
    static let scheme = "anyrouter"
    /// A link has to stay small enough to open reliably.
    static let maxTextLength = 1_500

    static var shareURL: URL { URL(string: "\(scheme)://share")! }

    static func askURL(text: String, action: ShareAction) -> URL? {
        guard !text.isEmpty, text.count <= maxTextLength else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = "ask"
        parts.queryItems = [URLQueryItem(name: "text", value: text), URLQueryItem(name: "action", value: action.rawValue)]
        return parts.url
    }

    static func parse(_ url: URL) -> (text: String, action: ShareAction)? {
        guard url.scheme == scheme, url.host == "ask",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let text = items.first(where: { $0.name == "text" })?.value, !text.isEmpty
        else { return nil }
        let name = items.first(where: { $0.name == "action" })?.value
        return (text, ShareAction.allCases.first { $0.rawValue == name } ?? .ask)
    }
}

/// What the extension tells the person when it cannot hand a share over.
enum ShareMessages {
    static func noAppGroup(hasFiles: Bool) -> String {
        hasFiles
            ? "Images and PDFs reach AnyRouter through an App Group, which this build does not have. Open AnyRouter and attach the file there, or use the TestFlight build."
            : "This build has no App Group and the text is too long to send in a link. Copy it, open AnyRouter and paste it."
    }

    static let saveFailed = "Could not save the share. Try again."
}
