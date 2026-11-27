import Foundation
import Observation

/// Reads replies aloud, one sentence at a time, with the engine `VoiceHub` picks for each sentence's language.
/// Works on a whole message (the speaker button) and on a reply that is still streaming ("Read replies aloud").
/// One speaker for the app: there is one set of speakers.
@MainActor @Observable
final class ReplySpeaker {
    /// The message being read, from the first sentence until the last one has been spoken.
    private(set) var speakingID: UUID?
    /// What went wrong the last time, in words the reader can act on. Cleared by the next read.
    private(set) var notice: String?

    @ObservationIgnored private var feeder = ReplyFeeder()
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var player: Task<Void, Never>?
    @ObservationIgnored private var engine: (any TextToSpeech)?
    @ObservationIgnored private var hub: VoiceHub?
    @ObservationIgnored private var lastLanguage: VoiceLanguage?
    @ObservationIgnored private var replyEnded = false
    /// Bumped by every stop, so the end of an old player cannot clear the state of a new one.
    @ObservationIgnored private var generation = 0

    var isSpeaking: Bool { speakingID != nil }

    /// The speaker button: read this message, or stop if it is the one being read.
    func toggle(messageID: UUID, text: String, hub: VoiceHub) {
        if speakingID == messageID {
            stop()
            return
        }
        begin(messageID, hub: hub)
        feed(messageID, text, isFinal: true)
    }

    /// A reply that is arriving. `text` is everything so far; `isFinal` when the reply is complete.
    /// A reply that follows one whose text is all in hand (a queued message sent as it ended) is read after its last
    /// sentences. A reply still arriving is cut off.
    func follow(messageID: UUID, text: String, isFinal: Bool, hub: VoiceHub) {
        if speakingID != messageID {
            if speakingID != nil && replyEnded { readNext(messageID) } else { begin(messageID, hub: hub) }
        }
        feed(messageID, text, isFinal: isFinal)
    }

    /// Stops the voice and forgets what was queued.
    func stop() {
        generation += 1
        queue.removeAll()
        player?.cancel()
        player = nil
        engine?.stop()
        engine = nil
        speakingID = nil
        replyEnded = false
        feeder = ReplyFeeder()
    }

    func dismissNotice() { notice = nil }

    func setNotice(_ text: String?) { notice = text }

    /// The line shown when no voice exists for a language on this device.
    static func missingVoiceNotice(_ language: VoiceLanguage) -> String {
        "No \(language.name) voice is installed. Add one in Settings, Accessibility, Spoken Content, Voices."
    }

    // MARK: Internals

    private func begin(_ messageID: UUID, hub: VoiceHub) {
        stop()
        self.hub = hub
        notice = nil
        speakingID = messageID
    }

    private func readNext(_ messageID: UUID) {
        speakingID = messageID
        replyEnded = false
    }

    private func feed(_ messageID: UUID, _ text: String, isFinal: Bool) {
        guard speakingID == messageID else { return }
        queue += feeder.update(messageID: messageID, text: text, isFinal: isFinal)
        if isFinal { replyEnded = true }
        if player != nil { return }
        if queue.isEmpty {
            if replyEnded { speakingID = nil }
            return
        }
        let session = generation
        player = Task { await play(session) }
    }

    private func play(_ session: Int) async {
        while session == generation, !queue.isEmpty, let hub {
            let sentence = queue.removeFirst()
            let language = VoiceLanguageDetector.dominant(sentence) ?? lastLanguage ?? VoiceLanguage.device
            lastLanguage = language
            let (engine, _) = hub.textToSpeech(for: language)
            self.engine = engine
            do {
                try await engine.speak(sentence, language: language)
            } catch let error as VoiceError {
                if case .languageUnavailable(let missing) = error { notice = Self.missingVoiceNotice(missing) } else { notice = error.errorDescription }
            } catch {
                notice = error.localizedDescription
                break
            }
        }
        guard session == generation else { return }
        engine = nil
        player = nil
        if replyEnded && queue.isEmpty { speakingID = nil }
    }
}
