import Foundation

/// A short instruction for the on-device model when it is offered tools. Without it the small model tends to wrap a tool's
/// answer in unrelated chat: asked for the time, it talked about a city it guessed from the time zone. Only added when
/// tools are offered, so plain chat is unchanged.
enum AppleToolGuidance {
    static let text = "You can call tools. When a tool gives you a result, answer in one or two short sentences "
        + "using exactly the values it returned. Do not add places, names or facts the tool did not give."

    static func instructions(base: String?, offeringTools: Bool) -> String? {
        guard offeringTools else { return base }
        guard let base, !base.isEmpty else { return text }
        return base + "\n\n" + text
    }
}
