import Foundation

/// The one line that stands for a finished tool chain: "Searched the web, read 3 pages, and 2 more steps".
/// Pure and built from localized phrases: each phrase, and each way of joining two or three of them, is its own string,
/// so a translation can reorder the words.
enum ToolSummary {
    /// Phrases shown before the rest fold into "N more steps".
    static let maxPhrases = 2

    private enum Kind: Hashable {
        case search, page, file, calculation, clock
        case other(String)
    }

    /// The summary of `steps`, in the order each kind of call first appears. Empty for no steps.
    static func text(for steps: [ToolStep]) -> String {
        var order: [Kind] = []
        var counts: [Kind: Int] = [:]
        for step in steps {
            let kind = kind(of: step.call.name)
            if counts[kind] == nil { order.append(kind) }
            counts[kind, default: 0] += 1
        }
        var parts = order.prefix(maxPhrases).map { phrase($0, count: counts[$0, default: 0]) }
        let hidden = order.dropFirst(maxPhrases).reduce(0) { $0 + counts[$1, default: 0] }
        if hidden > 0 { parts.append(hidden == 1 ? String(localized: "1 more step") : String(localized: "\(hidden) more steps")) }
        let joined: String
        switch parts.count {
        case 0: return ""
        case 1: joined = parts[0]
        case 2: joined = String(localized: "\(parts[0]) and \(parts[1])")
        default: joined = String(localized: "\(parts[0]), \(parts[1]), and \(parts[2])")
        }
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    private static func kind(of toolName: String) -> Kind {
        let name = toolName.lowercased()
        if name.contains("search") { return .search }
        switch name {
        case "fetch_url": return .page
        case "read_attachment": return .file
        case "calculator": return .calculation
        case "current_date_time": return .clock
        default: return .other(toolName)
        }
    }

    private static func phrase(_ kind: Kind, count: Int) -> String {
        switch kind {
        case .search: return String(localized: "searched the web")
        case .page: return count == 1 ? String(localized: "read 1 page") : String(localized: "read \(count) pages")
        case .file: return count == 1 ? String(localized: "read 1 file") : String(localized: "read \(count) files")
        case .calculation: return String(localized: "did the math")
        case .clock: return String(localized: "checked the time")
        case .other(let name): return String(localized: "used \(ToolRowLogic.displayName(for: name))")
        }
    }
}
