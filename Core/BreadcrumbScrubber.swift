import Foundation

/// Removes what must never leave the device from breadcrumb text and data: query strings and fragments of
/// URLs (they carry tokens and codes) and bearer tokens.
enum BreadcrumbScrubber {
    private static let urlQuery = #"(https?://[^\s?#"'<>]*)[?#][^\s"'<>]*"#
    private static let bearer = #"(?i)bearer\s+[A-Za-z0-9._~+/=-]+"#

    static func scrub(_ text: String) -> String {
        text
            .replacingOccurrences(of: urlQuery, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: bearer, with: "Bearer [redacted]", options: .regularExpression)
    }

    /// Strings and URLs are scrubbed. Numbers, bools and anything else pass through unchanged.
    static func scrub(data: [String: Any]?) -> [String: Any]? {
        data?.mapValues { value in
            if let text = value as? String { return scrub(text) }
            if let url = value as? URL { return scrub(url.absoluteString) }
            return value
        }
    }
}
