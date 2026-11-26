import Foundation

/// Short lines shown under the home greeting when it is tapped. Plain and friendly.
enum HomeTips {
    static let all: [String] = [
        "Long-press a message to copy it",
        "Ask me to explain anything like you're five",
        "Swipe a chat in the sidebar to pin or delete it",
        "Pull down on the model list to refresh it",
        "Tap the model name to switch models",
        "Small on-device models work without a connection",
        "Ask for a summary of a long text, then paste it in",
        "Try asking for a step-by-step plan",
        "You can ask me to answer in a different tone",
        "Say \"shorter\" to get a tighter answer",
        "Ask me to turn notes into a checklist",
        "Need a name for something? Ask for ten ideas",
        "Paste an error message and ask what it means",
        "Ask me to compare two options in a table",
        "Presets are handy for questions you ask often",
        "Cloud models are one sign-in away in Settings",
        "Ask for an example, then ask for a harder one",
        "I can help you rehearse a conversation",
        "Try asking for a recipe from what is in your fridge",
        "Ask me to proofread a paragraph",
        "Long chats get slower. Start a new one for a new topic",
        "Ask why, as many times as you like",
        "Use Search in the sidebar to find an old chat",
        "Turn on Show keyboard on launch in Settings",
        "Ask me to quiz you on something you are learning",
        "I can explain a word, an idiom or a joke",
        "Ask for a packing list for your next trip",
        "Try asking me to rewrite something more politely",
        "Ask for pros and cons before a big decision",
        "Not sure where to start? Ask what I can do",
    ]

    /// A random tip that differs from `current`, so two taps never show the same line twice in a row.
    static func next(after current: String?, using generator: inout some RandomNumberGenerator) -> String {
        let pool = all.filter { $0 != current }
        return pool.randomElement(using: &generator) ?? all[0]
    }

    static func next(after current: String?) -> String {
        var generator = SystemRandomNumberGenerator()
        return next(after: current, using: &generator)
    }
}
