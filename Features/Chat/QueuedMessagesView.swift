import SwiftUI

/// Messages waiting for the reply to end, as compact rows above the composer. A held queue (after Stop or a failed
/// reply) shows "Send queued (n)".
struct QueuedMessagesView: View {
    let model: ChatViewModel
    @State private var editing: QueueItem?
    @State private var draft = ""

    var body: some View {
        let queue = model.queue
        VStack(spacing: 6) {
            ForEach(queue.items) { item in row(item) }
            if model.queueIsHeld {
                Button(QueueLogic.resumeTitle(count: queue.items.count), systemImage: "paperplane") { model.resumeQueue() }
                    .buttonStyle(.glass)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("chat.queue.resume")
            }
        }
        .alert("Edit queued message", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Message", text: $draft)
            Button("Save") {
                if let editing { model.editQueued(editing.id, text: draft) }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        }
    }

    private func row(_ item: QueueItem) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text.isEmpty ? "Attachment" : item.text)
                    .font(.subheadline)
                    .lineLimit(2)
                if !item.attachments.isEmpty {
                    Label(String(item.attachments.count), systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            // One visible action per row; Send now and Edit are in the long-press menu (Apple's rule: one primary action).
            iconButton("Remove", "xmark", id: "chat.queue.remove") { model.removeQueued(item.id) }
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
        .contextMenu {
            Button("Send Now", systemImage: "arrow.up.circle") { model.sendQueuedNow(item.id) }
                .accessibilityIdentifier("chat.queue.sendNow")
            Button("Edit", systemImage: "pencil") {
                draft = item.text
                editing = item
            }
            .accessibilityIdentifier("chat.queue.edit")
            Button("Remove", systemImage: "xmark", role: .destructive) { model.removeQueued(item.id) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.queue.row")
    }

    private func iconButton(_ title: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityIdentifier(id)
    }
}
