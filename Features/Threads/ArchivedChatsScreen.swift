import SwiftData
import SwiftUI

/// The chats the user archived, newest first, pushed from "Archived chats" at the end of View all.
/// Each row has the same menu as everywhere, with Unarchive in place of Archive.
struct ArchivedChatsScreen: View {
    @Environment(ShellModel.self) private var shell
    @Query(sort: \ThreadRecord.updatedAt, order: .reverse) private var threads: [ThreadRecord]
    @State private var editing = ThreadEditing()

    var body: some View {
        let archived = ThreadListLogic.archived(from: threads)
        List(archived) { thread in
            Button { shell.openFromSearch(threadID: thread.id) } label: {
                Text(thread.title).lineLimit(1)
            }
            .foregroundStyle(.primary)
            .threadActions(thread, editing: $editing)
        }
        .listStyle(.plain)
        .navigationTitle("Archived chats")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if archived.isEmpty {
                ContentUnavailableView("No archived chats", systemImage: "archivebox")
            }
        }
        .threadEditingDialogs($editing)
    }
}
