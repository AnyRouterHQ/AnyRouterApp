import Foundation

/// What a pasted string is, found on the device. Only plain text goes on to a decision model.
enum PasteKind: Equatable, Sendable {
    case json(pretty: String)
    case jwt(header: String, payload: String, expiry: Date?)
    case cron(fields: [PasteField], summary: String)
    case stackTrace(language: String, frames: [String])
    case color(hex: String, rgb: String)
    case text
}

/// One labelled line of a detection result.
struct PasteField: Equatable, Sendable {
    var name: String
    var value: String
}

enum PasteLogic {
    static func detect(_ input: String) -> PasteKind {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let kind = color(text) { return kind }
        if let kind = jwt(text) { return kind }
        if let kind = json(text) { return kind }
        if let kind = cron(text) { return kind }
        if let kind = stackTrace(text) { return kind }
        return .text
    }

    // MARK: Color

    private static func color(_ text: String) -> PasteKind? {
        let channels: [Int]
        if let hex = captures(#"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$"#, in: text)?.first {
            let full = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
            channels = stride(from: 0, to: 6, by: 2).compactMap { offset in
                let start = full.index(full.startIndex, offsetBy: offset)
                return Int(full[start..<full.index(start, offsetBy: 2)], radix: 16)
            }
        } else if let rgb = captures(#"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*[\d.]+\s*)?\)$"#, in: text) {
            channels = rgb.compactMap { Int($0) }
            guard channels.allSatisfy({ $0 <= 255 }) else { return nil }
        } else {
            return nil
        }
        let hex = "#" + channels.map { ($0 < 16 ? "0" : "") + String($0, radix: 16, uppercase: true) }.joined()
        return .color(hex: hex, rgb: "rgb(" + channels.map(String.init).joined(separator: ", ") + ")")
    }

    // MARK: JWT and JSON

    private static func jwt(_ text: String) -> PasteKind? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let header = object(base64URL: parts[0]), header["alg"] != nil,
              let payload = object(base64URL: parts[1]),
              let headerText = pretty(header), let payloadText = pretty(payload) else { return nil }
        let expiry = (payload["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return .jwt(header: headerText, payload: payloadText, expiry: expiry)
    }

    private static func object(base64URL part: String) -> [String: Any]? {
        var base64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func json(_ text: String) -> PasteKind? {
        guard let first = text.first, "{[".contains(first), let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data), let formatted = pretty(value) else { return nil }
        return .json(pretty: formatted)
    }

    private static func pretty(_ value: Any) -> String? {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? JSONSerialization.data(withJSONObject: value, options: options)).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: Cron

    private static let cronFields: [(name: String, range: ClosedRange<Int>)] = [
        ("Minute", 0...59), ("Hour", 0...23), ("Day of month", 1...31), ("Month", 1...12), ("Day of week", 0...7),
    ]
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private static func cron(_ text: String) -> PasteKind? {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5, text.contains(where: { "*/,-".contains($0) }),
              zip(parts, cronFields).allSatisfy({ validCron($0, in: $1.range) }) else { return nil }
        return .cron(fields: zip(parts, cronFields).map { PasteField(name: $1.name, value: $0) }, summary: cronSummary(parts))
    }

    /// Each comma item is `*`, a number or a range, with an optional `/step`, and every number is in range.
    private static func validCron(_ field: String, in range: ClosedRange<Int>) -> Bool {
        field.split(separator: ",", omittingEmptySubsequences: false).allSatisfy { item in
            guard let numbers = captures(#"^(?:\*|(\d+)(?:-(\d+))?)(?:/\d+)?$"#, in: String(item)) else { return false }
            return numbers.compactMap { Int($0) }.allSatisfy { range.contains($0) }
        }
    }

    static func cronSummary(_ fields: [String]) -> String {
        let (minute, hour, dayOfMonth, month, dayOfWeek) = (fields[0], fields[1], fields[2], fields[3], fields[4])
        if fields.allSatisfy({ $0 == "*" }) { return "Every minute" }
        if hour == "*", dayOfMonth == "*", month == "*", dayOfWeek == "*", minute.hasPrefix("*/"), let step = Int(minute.dropFirst(2)) {
            return "Every \(step) minutes"
        }
        if let m = Int(minute), let h = Int(hour), dayOfMonth == "*", month == "*" {
            let time = String(format: "%02ld:%02ld", h, m)
            if dayOfWeek == "*" { return "Every day at \(time)" }
            if let day = Int(dayOfWeek) { return "Every \(weekdays[day]) at \(time)" }
        }
        return "Minute \(minute), hour \(hour), day \(dayOfMonth), month \(month), weekday \(dayOfWeek)"
    }

    // MARK: Stack traces

    private static func stackTrace(_ text: String) -> PasteKind? {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let python = lines.filter { $0.hasPrefix("File \"") && $0.contains(", line ") }
        if lines.first?.hasPrefix("Traceback") == true, !python.isEmpty { return .stackTrace(language: "Python", frames: python) }
        let java = lines.filter { captures(#"^at [\w$.<>]+\([\w$]+\.(?:java|kt|scala):\d+\)$"#, in: $0) != nil }
        if java.count >= 2 { return .stackTrace(language: "Java", frames: java) }
        let script = lines.filter { captures(#"^at (?:.+ \()?[^\s()]+:\d+:\d+\)?$"#, in: $0) != nil }
        if script.count >= 2 { return .stackTrace(language: "JavaScript", frames: script) }
        return nil
    }

    // MARK: Text for the screen

    static func title(_ kind: PasteKind) -> String {
        switch kind {
        case .json: "JSON"
        case .jwt: "JWT"
        case .cron: "Cron schedule"
        case .stackTrace(let language, _): "\(language) stack trace"
        case .color: "Color"
        case .text: "Text"
        }
    }

    /// The lines the Paste card shows. Empty for plain text, which goes to a decision model instead.
    static func rows(_ kind: PasteKind, now: Date = .now) -> [PasteField] {
        switch kind {
        case .json(let pretty):
            return [PasteField(name: "Pretty", value: pretty)]
        case .jwt(let header, let payload, let expiry):
            var rows = [PasteField(name: "Header", value: header), PasteField(name: "Payload", value: payload)]
            if let expiry {
                let when = ISO8601DateFormatter().string(from: expiry)
                rows.append(PasteField(name: "Expiry", value: expiry < now ? "Expired \(when)" : "Expires \(when)"))
            }
            return rows
        case .cron(let fields, let summary):
            return [PasteField(name: "Runs", value: summary)] + fields
        case .stackTrace(let language, let frames):
            return [PasteField(name: "Language", value: language), PasteField(name: "Frames", value: frames.joined(separator: "\n"))]
        case .color(let hex, let rgb):
            return [PasteField(name: "Hex", value: hex), PasteField(name: "RGB", value: rgb)]
        case .text:
            return []
        }
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}
