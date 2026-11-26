import Foundation

/// "Switched to <model>" notes: a reply written by another model than the one before it.
enum SwitchNotes {
    /// Maps a reply's id to the note shown above it.
    static func make(_ messages: [MessageRecord]) -> [UUID: String] {
        var notes: [UUID: String] = [:]
        var previous: String?
        for message in messages where message.role == .assistant {
            guard let id = message.modelID else { continue }
            if let previous, previous != id {
                notes[message.id] = "Switched to \(message.modelName ?? id)"
            }
            previous = id
        }
        return notes
    }
}
