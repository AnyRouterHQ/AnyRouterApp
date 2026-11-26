import Foundation
import Testing
@testable import AnyRouter

struct ReplyFeederTests {
    private let first = UUID()

    @Test func aGrowingReplyGivesEachSentenceOnce() {
        var feeder = ReplyFeeder()
        let full = "The first sentence is long enough to speak. The second one follows right after it. Done."
        var heard: [String] = []
        for end in stride(from: 10, through: full.count, by: 10) { heard += feeder.update(messageID: first, text: String(full.prefix(end)), isFinal: false) }
        heard += feeder.update(messageID: first, text: full, isFinal: true)
        #expect(heard == ["The first sentence is long enough to speak.", "The second one follows right after it.", "Done."])
        #expect(feeder.update(messageID: first, text: full, isFinal: true).isEmpty, "a repeated final adds nothing")
    }

    @Test func anotherMessageOrAShorterTextStartsOver() {
        var feeder = ReplyFeeder()
        let text = "The first sentence is long enough to speak. And more."
        #expect(feeder.update(messageID: first, text: text, isFinal: true).count == 2)
        #expect(feeder.update(messageID: UUID(), text: text, isFinal: true).count == 2)
        let id = UUID()
        _ = feeder.update(messageID: id, text: text, isFinal: false)
        #expect(feeder.update(messageID: id, text: "Hello there my friend.", isFinal: true) == ["Hello there my friend."])
    }
}

@MainActor
struct ReplySpeakerTests {
    private struct Rig {
        let speaker = ReplySpeaker()
        let hub: VoiceHub
        let voice: FakeTextToSpeech
    }

    private func rig(supported: Set<VoiceLanguage> = [.english, .vietnamese]) -> Rig {
        let voice = FakeTextToSpeech(id: "system", supported: supported)
        let hub = VoiceHub(
            settings: VoiceSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!), catalog: { [] },
            systemSTT: { FakeSpeechToText() }, systemTTS: { voice })
        return Rig(hub: hub, voice: voice)
    }

    private let english = "The weather is lovely today, so we will walk to the park together."
    private let vietnamese = "Hôm nay trời đẹp quá, chúng ta hãy cùng nhau đi dạo trong công viên nhé."

    @Test func aWholeMessageIsReadSentenceBySentenceEachInItsOwnLanguage() async {
        let r = rig()
        let id = UUID()
        r.speaker.toggle(messageID: id, text: english + " " + vietnamese, hub: r.hub)
        #expect(r.speaker.isSpeaking && r.speaker.speakingID == id)
        await settle { r.speaker.speakingID == nil }
        #expect(r.voice.spoken.map(\.text) == [english, vietnamese])
        #expect(r.voice.spoken.map(\.language) == [.english, .vietnamese])
    }

    @Test func theSpeakerButtonStopsTheMessageItIsReading() async {
        let r = rig()
        r.voice.holds = true
        let id = UUID()
        r.speaker.toggle(messageID: id, text: english + " " + english + " Again.", hub: r.hub)
        await settle { r.voice.spoken.count == 1 }
        r.speaker.toggle(messageID: id, text: english, hub: r.hub)
        #expect(r.speaker.speakingID == nil)
        #expect(r.voice.stopCount >= 1)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(r.voice.spoken.count == 1, "nothing queued is spoken after stop")
    }

    @Test func aStreamingReplyIsSpokenAsSentencesCompleteAndEndsWithTheLastOne() async {
        let r = rig()
        let id = UUID()
        r.speaker.follow(messageID: id, text: english + " The second sentence is still arr", isFinal: false, hub: r.hub)
        await settle { r.voice.spoken.count == 1 }
        #expect(r.voice.spoken[0].text == english)
        #expect(r.speaker.speakingID == id, "still waiting for the rest of the reply")
        r.speaker.follow(messageID: id, text: english + " The second sentence is still arriving, then it ends.", isFinal: true, hub: r.hub)
        await settle { r.speaker.speakingID == nil }
        #expect(r.voice.spoken.map(\.text) == [english, "The second sentence is still arriving, then it ends."])
    }

    @Test func aReplyThatEndsWithNothingNewLeavesNoSpeakingMessage() async {
        let r = rig()
        let id = UUID()
        r.speaker.follow(messageID: id, text: english + " ", isFinal: false, hub: r.hub)
        await settle { r.voice.spoken.count == 1 && r.speaker.speakingID == id }
        r.speaker.follow(messageID: id, text: english + " ", isFinal: true, hub: r.hub)
        await settle { r.speaker.speakingID == nil }
        #expect(r.speaker.speakingID == nil)
    }

    @Test func aLanguageWithNoVoiceIsSkippedWithANoticeAndTheRestIsStillRead() async {
        let r = rig(supported: [.english])
        r.speaker.toggle(messageID: UUID(), text: vietnamese + " " + english, hub: r.hub)
        await settle { r.speaker.speakingID == nil }
        #expect(r.voice.spoken.map(\.text) == [english])
        #expect(r.speaker.notice == ReplySpeaker.missingVoiceNotice(.vietnamese))
        r.speaker.dismissNotice()
        #expect(r.speaker.notice == nil)
    }

    @Test func aNewMessageCutsOffTheOldOne() async {
        let r = rig()
        r.voice.holds = true
        let old = UUID()
        let new = UUID()
        r.speaker.follow(messageID: old, text: english + " More text follows here.", isFinal: false, hub: r.hub)
        await settle { r.voice.spoken.count == 1 }
        r.speaker.follow(messageID: new, text: english, isFinal: true, hub: r.hub)
        #expect(r.speaker.speakingID == new)
        #expect(r.voice.stopCount >= 1)
        r.speaker.stop()
        #expect(!r.speaker.isSpeaking)
    }

    @Test func theNoticeNamesTheLanguageAndWhereToGetTheVoice() {
        let notice = ReplySpeaker.missingVoiceNotice(.vietnamese)
        #expect(notice.contains(VoiceLanguage.vietnamese.name) && notice.contains("Spoken Content"))
    }

    @Test func stoppingWhileIdleIsHarmless() {
        let speaker = ReplySpeaker()
        speaker.stop()
        #expect(!speaker.isSpeaking && speaker.notice == nil)
    }
}
