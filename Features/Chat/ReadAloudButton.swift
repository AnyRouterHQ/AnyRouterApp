import SwiftUI

/// Under a reply: reads it aloud, or stops reading it.
struct ReadAloudButton: View {
    let message: MessageRecord
    @Environment(AppState.self) private var app

    var body: some View {
        let speaking = app.speaker.speakingID == message.id
        Button {
            app.speaker.toggle(messageID: message.id, text: message.content, hub: app.voice)
        } label: {
            Label(speaking ? "Stop reading" : "Read aloud", systemImage: speaking ? "stop.circle" : "speaker.wave.2")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        // The HIG minimum hit area; a borderless button is only as big as its symbol.
        .frame(minWidth: 44, minHeight: 44)
        .hoverEffect(.highlight)
        .accessibilityIdentifier("reply.readAloud")
    }
}
