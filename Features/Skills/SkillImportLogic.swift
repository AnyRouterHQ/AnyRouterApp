import Foundation

enum SkillImportError: Error, Equatable, LocalizedError {
    case notHTTPS, http(Int), notText, tooLarge, unreadable

    var errorDescription: String? {
        switch self {
        case .notHTTPS: "Use a link that starts with https://."
        case .http(let status): "The server answered with HTTP \(status)."
        case .notText: "The link must serve plain text or Markdown."
        case .tooLarge: "The file is larger than 64 KB."
        case .unreadable: "The file could not be read as text."
        }
    }
}

/// The rules for importing a SKILL.md from a link (agent design 4.2, unit K2). The file is untrusted: it is fetched with no
/// cookies and no credentials, capped while it downloads, and parsed and checked before it is shown for approval.
enum SkillImportLogic {
    static let sizeLimit = 64 * 1024
    static let allowedTypes = ["text/markdown", "text/plain"]
    static let previewLines = 6
    static let previewCharacters = 400

    /// The link as typed, trimmed. Only https links are fetched.
    static func url(from text: String) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            throw SkillImportError.notHTTPS
        }
        return url
    }

    /// Checks a response before its body is read. `finalURL` is where redirects ended; `length` is -1 when unknown.
    static func check(finalURL: URL?, status: Int, contentType: String?, length: Int64) throws {
        guard finalURL?.scheme?.lowercased() == "https" else { throw SkillImportError.notHTTPS }
        guard (200..<300).contains(status) else { throw SkillImportError.http(status) }
        let type = contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        guard let type, allowedTypes.contains(type) else { throw SkillImportError.notText }
        guard length <= Int64(sizeLimit) else { throw SkillImportError.tooLarge }
    }

    static func text(from data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else { throw SkillImportError.unreadable }
        return text
    }

    /// What the user reads before saving: the name, the description and the first lines of the steps.
    static func preview(_ draft: SkillDraft) -> String {
        let lines = draft.body.split(separator: "\n", omittingEmptySubsequences: false)
        var excerpt = lines.prefix(previewLines).joined(separator: "\n")
        var more = lines.count > previewLines
        if excerpt.count > previewCharacters {
            excerpt = String(excerpt.prefix(previewCharacters))
            more = true
        }
        return "\(draft.name)\n\(draft.description)\n\n\(excerpt)" + (more ? "\n\u{2026}" : "")
    }
}

/// Downloads a SKILL.md. The session keeps no cookies and no cache, so nothing of the user's travels with the request.
struct SkillImporter: Sendable {
    var session: URLSession = SkillImporter.privateSession()

    static func privateSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("text/markdown, text/plain", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw SkillImportError.unreadable }
        try SkillImportLogic.check(
            finalURL: http.url, status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"),
            length: http.expectedContentLength)
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > SkillImportLogic.sizeLimit { throw SkillImportError.tooLarge }
        }
        return try SkillImportLogic.text(from: data)
    }
}
