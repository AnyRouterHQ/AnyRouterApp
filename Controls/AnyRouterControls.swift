import AppIntents
import SwiftUI
import WidgetKit

@main
struct ControlsBundle: WidgetBundle {
    var body: some Widget {
        NewChatControl()
        VoiceControl()
        PasteAndFixControl()
    }
}

struct NewChatControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "oneni.anyr.app.controls.new-chat") {
            ControlWidgetButton(action: NewChatControlIntent()) {
                Label("New chat", systemImage: "square.and.pencil")
            }
        }
        .displayName("New chat")
        .description("Open AnyRouter on a new chat.")
    }
}

struct VoiceControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "oneni.anyr.app.controls.voice") {
            ControlWidgetButton(action: VoiceControlIntent()) {
                Label("Voice", systemImage: "waveform")
            }
        }
        .displayName("Voice")
        .description("Open AnyRouter on a new chat, ready to dictate.")
    }
}

struct PasteAndFixControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "oneni.anyr.app.controls.paste-and-fix") {
            ControlWidgetButton(action: PasteAndFixControlIntent()) {
                Label("Paste & fix", systemImage: "text.badge.checkmark")
            }
        }
        .displayName("Paste & fix")
        .description("Paste a text and have AnyRouter fix its English.")
    }
}
