import Foundation

/// Reads one web page as text. https only, no local network, capped in time and size.
struct FetchURLTool: BuiltInTool {
    static let toolName = "fetch_url"
    let name = FetchURLTool.toolName
    let title = "Read a web page"
    let summary = "Fetch a page and read its text (https only)"
    let description = "Fetch a web page over https and return its readable text. Use it to read a link the user gave you or a search result."
    let inputSchemaJSON = #"{"type":"object","properties":{"url":{"type":"string","description":"The https URL to read"}},"required":["url"]}"#

    var session: URLSession = .shared
    var timeout: TimeInterval = 15
    var maxBytes = 1_000_000
    var maxCharacters = 12_000

    func run(_ arguments: JSONValue) async throws -> String {
        guard let text = arguments["url"]?.string, !text.isEmpty else { throw BuiltInToolError("Missing the \"url\" argument.") }
        let url: URL
        switch FetchURLPolicy.validate(text) {
        case .success(let value): url = value
        case .failure(let problem): throw BuiltInToolError(problem.message)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("text/html, text/plain, application/json;q=0.9, */*;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue("AnyRouter for iOS", forHTTPHeaderField: "User-Agent")

        let fetched: (URLSession.AsyncBytes, URLResponse)
        do {
            fetched = try await session.bytes(for: request, delegate: RedirectGuard())
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw BuiltInToolError("Could not load the page: \(error.localizedDescription)")
        }
        let (bytes, response) = fetched
        guard let http = response as? HTTPURLResponse else { throw BuiltInToolError("Not an HTTP answer.") }
        guard (200..<300).contains(http.statusCode) else { throw BuiltInToolError("The page answered HTTP \(http.statusCode).") }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard type.isEmpty || type.contains("text/") || type.contains("json") || type.contains("xml") else {
            throw BuiltInToolError("Cannot read this content type: \(type).")
        }

        var data = Data()
        var truncated = false
        for try await byte in bytes {
            data.append(byte)
            if data.count >= maxBytes { truncated = true; break }
        }
        let body = String(decoding: data, as: UTF8.self)
        let isHTML = type.contains("html") || (type.isEmpty && body.lowercased().contains("<html"))
        let readable = isHTML ? HTMLText.readable(body) : body
        var out = "URL: \(http.url?.absoluteString ?? url.absoluteString)\n"
        if isHTML, let title = HTMLText.title(in: body) { out += "Title: \(title)\n" }
        out += "\n" + clippedText(readable, limit: maxCharacters)
        if truncated { out += "\n[The page was larger than \(maxBytes / 1000) KB; the rest was not read.]" }
        return out
    }

    /// Refuses a redirect to a URL the policy would not allow (http, the local network).
    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let target = request.url, case .success = FetchURLPolicy.validate(target.absoluteString) else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }
    }
}

enum FetchURLPolicy {
    struct Problem: Error, Equatable {
        let message: String
    }

    static func validate(_ text: String) -> Result<URL, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host()?.lowercased(), !host.isEmpty else {
            return .failure(Problem(message: "That is not a valid URL."))
        }
        guard scheme == "https" else { return .failure(Problem(message: "Only https URLs can be read.")) }
        guard !isLocal(host: host) else { return .failure(Problem(message: "Addresses on this device or its network cannot be read.")) }
        return .success(url)
    }

    /// Localhost, `.local`/`.internal` names, private and link-local IPv4, loopback and private IPv6.
    static func isLocal(host: String) -> Bool {
        let host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") { return true }
        if host.contains(":") {
            return host == "::1" || host == "::" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80")
                || host.hasPrefix("::ffff:")
        }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return true
        case (172, 16...31): return true
        case (100, 64...127): return true
        default: return false
        }
    }
}
