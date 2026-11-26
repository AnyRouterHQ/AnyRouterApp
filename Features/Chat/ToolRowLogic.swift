import Foundation

/// Titles and text for the tool rows in a message. Pure, so it is easy to test.
enum ToolRowLogic {
    /// Result text of a call that was cut off by Stop.
    static let cancelledText = "Cancelled"
    /// Longest result text a row shows.
    static let maxResultCharacters = 2_000

    enum Status: Equatable { case running, done, failed, cancelled }

    private enum Kind {
        case search, read, other

        init(toolName: String) {
            let name = toolName.lowercased()
            if name.contains("search") {
                self = .search
            } else if ["scrape", "crawl", "fetch"].contains { name.contains($0) } {
                self = .read
            } else {
                self = .other
            }
        }

        var running: String {
            switch self {
            case .search: "Searching the web"
            case .read: "Reading a page"
            case .other: "Using a tool"
            }
        }

        var done: String {
            switch self {
            case .search: "Searched the web"
            case .read: "Read a page"
            case .other: "Used a tool"
            }
        }

        var noun: String {
            switch self {
            case .search: "Search"
            case .read: "Read"
            case .other: "Tool"
            }
        }
    }

    static func status(of step: ToolStep) -> Status {
        guard let result = step.result else { return .running }
        if !result.isError { return .done }
        return result.text == cancelledText ? .cancelled : .failed
    }

    /// For example "Searching the web · firecrawl_search".
    static func title(for step: ToolStep) -> String {
        let kind = Kind(toolName: step.call.name)
        let phrase: String
        switch status(of: step) {
        case .running: phrase = kind.running
        case .done: phrase = kind.done
        case .failed: phrase = "\(kind.noun) failed"
        case .cancelled: phrase = "\(kind.noun) cancelled"
        }
        return "\(phrase) · \(step.call.name)"
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
