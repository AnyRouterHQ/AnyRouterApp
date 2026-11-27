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
            Label(speaking ? "Stop reading" : "Read aloud", systemImage: speaking ? "stop" : "play")
                .labelStyle(.iconOnly)
                // The HIG minimum hit area, inside the label so the button itself is 44 pt.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .hoverEffect(.highlight)
        .accessibilityIdentifier("reply.readAloud")
    }
}
