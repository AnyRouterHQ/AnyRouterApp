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
        let binary = tokens % 1024 == 0
        if tokens >= 1_000_000 {
            return trimmed(Double(tokens) / (binary ? 1_048_576 : 1_000_000)) + "M ctx"
        }
        if tokens >= 1000 {
            return trimmed(Double(tokens) / (binary ? 1024 : 1000)) + "K ctx"
        }
        return "\(tokens) ctx"
    }

    /// "$0.0004" for a request cost, "Free" for zero.
    static func cost(_ value: Decimal) -> String {
        if value == 0 { return "Free" }
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
