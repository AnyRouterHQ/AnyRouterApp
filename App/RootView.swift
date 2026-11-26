import SwiftData
import SwiftUI

/// Placeholder shell. Lane D replaces the content with the real threads and chat screens.
struct RootView: View {
    @Query(sort: \ThreadRecord.updatedAt, order: .reverse) private var threads: [ThreadRecord]

    var body: some View {
        NavigationSplitView {
            List(threads) { thread in
                Text(thread.title)
            }
            .navigationTitle("AnyRouter")
            .overlay {
                if threads.isEmpty {
                    ContentUnavailableView("No chats yet", systemImage: "bubble.left.and.bubble.right")
                }
            }
        } detail: {
            ContentUnavailableView("AnyRouter", systemImage: "sparkles", description: Text("Select or start a chat."))
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [ThreadRecord.self, MessageRecord.self], inMemory: true)
}
