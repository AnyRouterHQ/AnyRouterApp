import SwiftUI

/// The preview that lifts out of a row on long press: the title and the last few turns.
struct ThreadMenuPreview: View {
    let thread: ThreadRecord

    private var turns: [MessageRecord] {
        let shown = thread.messages.filter { $0.role != .system && !$0.content.isEmpty }.sorted { $0.createdAt < $1.createdAt }
        return Array(shown.suffix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(thread.title).font(.headline).lineLimit(2)
            ForEach(turns) { message in
                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(message.role == .user ? .primary : .secondary)
                    .lineLimit(3)
            }
            if turns.isEmpty {
                Text("No messages yet").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(width: 300, alignment: .leading)
        .padding()
    }
}
