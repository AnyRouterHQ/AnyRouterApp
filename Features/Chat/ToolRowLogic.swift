import Foundation

/// Titles and text for the tool rows in a message. Pure, so it is easy to test.
enum ToolRowLogic {
    /// Result text of a call that was cut off by Stop.
    static let cancelledText = "Cancelled"
    /// Longest result text a row shows.
    static let maxResultCharacters = 2_000

    enum Status: Equatable { case running, done, failed, cancelled }

    static func status(of step: ToolStep) -> Status {
        guard let result = step.result else { return .running }
        if !result.isError { return .done }
        return result.text == cancelledText ? .cancelled : .failed
    }

    /// Longest query or expression shown in a title.
    static let maxTitleArgument = 60

    /// What the row says, for example "Searched the web for “swift 7”". Failed and cancelled calls say so at the end.
    static func title(for step: ToolStep) -> String {
        let state = status(of: step)
        let running = state == .running
        let phrase = phrase(for: step.call, running: running)
        switch state {
        case .running, .done: return phrase
        case .failed: return phrase + " failed"
        case .cancelled: return phrase + " cancelled"
        }
    }

    private static func phrase(for call: ToolCall, running: Bool) -> String {
        let args = arguments(of: call)
        func text(_ key: String) -> String? {
            guard let value = (args[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
            else { return nil }
            return value
        }
        let lowered = call.name.lowercased()
        switch lowered {
        case "web_search":
            let verb = running ? "Searching" : "Searched"
            guard let query = text("query") else { return "\(verb) the web" }
            return "\(verb) the web for “\(truncated(query))”"
        case "fetch_url":
            let verb = running ? "Reading" : "Read"
            return "\(verb) \(text("url").flatMap(shortURL) ?? "a page")"
        case "calculator":
            let verb = running ? "Calculating" : "Calculated"
            return text("expression").map { "\(verb) \(truncated($0))" } ?? "\(verb) a result"
        case "current_date_time":
            return running ? "Checking the date and time" : "Checked the date and time"
        case "read_attachment":
            let verb = running ? "Reading" : "Read"
            return "\(verb) \(text("name").map(truncated) ?? "the attachments")"
        default:
            if lowered.contains("search") { return running ? "Searching the web" : "Searched the web" }
            return "\(running ? "Using" : "Used") \(call.name)"
        }
    }

    private static func arguments(of call: ToolCall) -> [String: Any] {
        guard let data = call.argumentsJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    /// Host and path of a URL without scheme or query: `https://example.com/a?b=1` becomes `example.com/a`.
    private static func shortURL(_ text: String) -> String? {
        guard let url = URL(string: text), let host = url.host() else { return nil }
        let path = url.path == "/" ? "" : url.path
        return truncated(host + path)
    }

    private static func truncated(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard flat.count > maxTitleArgument else { return flat }
        return String(flat.prefix(maxTitleArgument)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Indented JSON with sorted keys. Text that is not JSON comes back unchanged.
    static func prettyJSON(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
            let pretty = try? JSONSerialization.data(
                withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]),
            let string = String(data: pretty, encoding: .utf8)
        else { return text }
        return string
    }

    static func clipped(_ text: String, limit: Int = maxResultCharacters) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n[Cut at \(limit) characters.]"
    }
}
