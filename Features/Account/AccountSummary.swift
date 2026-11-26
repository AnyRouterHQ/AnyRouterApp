import Foundation

/// What the account card shows. Built once from the three AnyRouter endpoints so views never touch JSON.
struct AccountSummary: Equatable, Sendable {
    struct Credits: Equatable, Sendable {
        /// Remaining balance in USD.
        var balance: Double
        var used: Double?
    }

    struct FreeRequests: Equatable, Sendable {
        var remaining: Int
        var limit: Int
    }

    /// Spend on the sign-in key itself (`GET /api/v1/key`), used when credits are not readable.
    struct KeyUsage: Equatable, Sendable {
        var label: String?
        var limit: Double?
        var limitRemaining: Double?
        var usage: Double?
    }

    var displayName: String?
    var email: String?
    var avatarURL: URL?
    var plan: String?
    /// `email_verified` from /me. Nil when the server does not say, which counts as verified.
    var emailVerified: Bool?
    var credits: Credits?
    var freeRequests: FreeRequests?
    var keyUsage: KeyUsage?

    var isEmpty: Bool {
        displayName == nil && email == nil && avatarURL == nil && plan == nil
            && credits == nil && freeRequests == nil && keyUsage == nil
    }

    /// The server says the email is not verified yet. Chat keeps working; Settings asks once, quietly.
    var needsEmailVerification: Bool { emailVerified == false }

    /// Name, else email, else a neutral title.
    var title: String { displayName ?? email ?? "AnyRouter account" }

    /// Up to two letters for the avatar fallback.
    var initials: String {
        let source = displayName ?? email?.split(separator: "@").first.map(String.init) ?? ""
        let letters = source.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2).compactMap(\.first)
        return letters.isEmpty ? "A" : String(letters).uppercased()
    }

    /// One line for the card: credits first, then free requests, then this key's usage.
    var usageLine: String? {
        if let credits { return "Credits: \(Self.money(credits.balance))" }
        if let freeRequests { return "\(freeRequests.remaining) of \(freeRequests.limit) free requests left" }
        if let key = keyUsage {
            if let remaining = key.limitRemaining, let limit = key.limit {
                return "Key: \(Self.money(remaining)) of \(Self.money(limit)) left"
            }
            if let usage = key.usage { return "Key usage: \(Self.money(usage))" }
        }
        return nil
    }

    /// The line under the name: email (when the name is not the email), then credits or usage, then the plan.
    var subtitle: String? {
        let parts = [email == title ? nil : email, usageLine, plan.map { "\($0) plan" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    // MARK: Parsing

    /// Parses each body on its own: a missing or malformed one only drops its fields.
    static func parse(me: Data?, credits: Data?, key: Data?) -> AccountSummary {
        var summary = AccountSummary()
        if let profile = object(me) {
            summary.displayName = string(profile, ["name", "display_name", "displayName", "username"])
            summary.email = string(profile, ["email"])
            summary.avatarURL = string(profile, ["image_url", "avatar_url", "avatarUrl", "image", "picture", "avatar"])
                .flatMap(URL.init(string:))
                .flatMap { $0.scheme == "https" ? $0 : nil }
            summary.plan = planName(profile)
            summary.emailVerified = profile["email_verified"] as? Bool
            // Sign-in keys get 403 on /credits, so /me's balance is the usual source.
            if let balance = number(profile, ["balance"]) { summary.credits = Credits(balance: balance, used: nil) }
        }
        if let credits = object(credits) {
            if let balance = number(credits, ["balance"]) {
                summary.credits = Credits(balance: balance, used: number(credits, ["used"]))
            }
            if let free = credits["free_requests"] as? [String: Any],
               let remaining = number(free, ["remaining"]), let limit = number(free, ["limit"]) {
                // Counts come from the server: clamp them so an absurd number cannot trap the conversion.
                summary.freeRequests = FreeRequests(remaining: Int(min(max(remaining, 0), 1e9)), limit: Int(min(max(limit, 0), 1e9)))
            }
        }
        if let key = object(key) {
            let usage = KeyUsage(
                label: string(key, ["label"]),
                limit: number(key, ["limit"]),
                limitRemaining: number(key, ["limit_remaining"]),
                usage: number(key, ["usage", "real_usage"])
            )
            if usage != KeyUsage() { summary.keyUsage = usage }
        }
        return summary
    }

    /// The JSON object, unwrapping a top-level `data` envelope when there is one.
    private static func object(_ data: Data?) -> [String: Any]? {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (root["data"] as? [String: Any]) ?? root
    }

    private static func string(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let text = (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }

    private static func number(_ dict: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            if let value = dict[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.doubleValue }
        }
        return nil
    }

    private static func planName(_ dict: [String: Any]) -> String? {
        for key in ["plan", "plan_name", "tier"] {
            if let text = dict[key] as? String, !text.isEmpty { return text.capitalized }
            if let nested = dict[key] as? [String: Any], let text = string(nested, ["name", "id", "slug"]) { return text.capitalized }
        }
        return nil
    }
}
