import Foundation

/// Compact text for price and context size in model rows.
enum PriceFormat {
    /// "$3", "$0.15", "$1.25", "$15". Small prices keep a third decimal ("$0.075").
    static func amount(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value < Decimal(string: "0.1")! ? 3 : 2
        return "$" + (formatter.string(from: number) ?? "\(value)")
    }

    /// "Free", "$3 / $15 per 1M", or nil when the catalog gave no price.
    static func line(_ pricing: CloudPricing) -> String? {
        if pricing.isFree { return "Free" }
        guard let input = pricing.input, let output = pricing.output else {
            return pricing.billing == .byok ? "Your key" : nil
        }
        return "\(amount(input)) / \(amount(output)) per 1M"
    }

    /// "1M ctx", "128K ctx". Powers of two (131072) and round numbers (128000) both read naturally.
    static func context(_ tokens: Int) -> String {
        func trimmed(_ value: Double) -> String {
            let rounded = (value * 10).rounded() / 10
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }
        // 8192, 131072 and 1048576 are binary sizes; 128000 and 1000000 are round decimal ones.
        let binary = tokens > 0 && ((tokens & (tokens - 1)) == 0 || tokens % 65_536 == 0)
        if tokens >= 1_000_000 {
            return trimmed(Double(tokens) / (binary ? 1_048_576 : 1_000_000)) + "M ctx"
        }
        if tokens >= 1000 {
            return trimmed(Double(tokens) / (binary ? 1024 : 1000)) + "K ctx"
        }
        return "\(tokens) ctx"
    }

    /// "950", "34K", "12.4B": a count with one decimal at most, for token and request totals.
    static func compactCount(_ value: Int) -> String {
        guard value >= 1000 else { return String(value) }
        // The cut-offs sit where rounding to one decimal reaches the next unit ("999,950" is "1M", not "1000K").
        let (unit, suffix) = value >= 999_950_000 ? (1e9, "B") : value >= 999_950 ? (1e6, "M") : (1e3, "K")
        let scaled = (Double(value) / unit * 10).rounded() / 10
        return (scaled == scaled.rounded() ? String(Int(scaled)) : String(scaled)) + suffix
    }

    /// "1,050,000": digits grouped by thousands.
    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// "$0.0004" for a request cost, "$0" for zero (a free model still shows what the reply cost).
    static func cost(_ value: Decimal) -> String {
        if value == 0 { return "$0" }
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = value < Decimal(string: "0.01")! ? 4 : 2
        return "$" + (formatter.string(from: number) ?? "\(value)")
    }
}
