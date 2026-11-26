import Foundation

/// Turns a reply that grows into the new sentences to speak. The caller passes the whole text so far each time;
/// a different message, or a text that got shorter (a regenerate), starts over.
struct ReplyFeeder: Sendable {
    private var messageID: UUID?
    private var fed = 0
    private var chunker = SentenceChunker()

    mutating func update(messageID: UUID, text: String, isFinal: Bool) -> [String] {
        if messageID != self.messageID || text.count < fed {
            self.messageID = messageID
            fed = 0
            chunker = SentenceChunker()
        }
        let delta = String(text.dropFirst(fed))
        fed = text.count
        var sentences = chunker.push(delta)
        if isFinal { sentences += chunker.finish() }
        return sentences
    }
}
