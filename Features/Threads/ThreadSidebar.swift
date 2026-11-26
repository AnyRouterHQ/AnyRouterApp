import SwiftData
import SwiftUI

/// Sidebar: a stock sidebar `List` with a large title, system search, a settings button and a
/// compose button in the bottom bar. On iPhone it fills the drawer, on iPad the split-view column.
struct ThreadSidebar: View {
    /// True when shown as a drawer over the chat (iPhone). Picking something then closes it.
    let isDrawer: Bool

    @Environment(ShellModel.self) private var shell
    @Environment(\.modelContext) private var context
    @Query(sort: \ThreadRecord.updatedAt, order: .reverse) private var threads: [ThreadRecord]

    @State private var query = ""
    @State private var isSearching = false
    @State private var renaming: ThreadRecord?
    @State private var renameText = ""
    @State private var deleting: ThreadRecord?

    private var sections: ThreadListLogic.Sections {
        ThreadListLogic.sections(from: threads, query: query)
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { shell.selectedThreadID },
            set: { if let id = $0 { shell.select(threadID: id, closeSidebar: isDrawer) } }
        )
    }

    var body: some View {
        // The iPad column already sits in a navigation context; the drawer needs its own.
        if isDrawer { NavigationStack { content } } else { content }
    }

    private var content: some View {
        List(selection: selection) {
            if sections.isEmpty {
                Text(query.isEmpty ? "No chats yet" : "No matching chats")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
            if !sections.pinned.isEmpty { Section("Pinned") { rows(sections.pinned) } }
            if !sections.recent.isEmpty { Section("Recents") { rows(sections.recent) } }
        }
        .listStyle(.sidebar)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("AnyRouter")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, isPresented: $isSearching, prompt: "Search chats")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { shell.presentSettings(closeSidebar: isDrawer) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button { shell.newChat(closeSidebar: isDrawer) } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
            }
        }
        .onChange(of: shell.searchRequest) { isSearching = true }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let thread = renaming { ThreadActions.rename(thread, to: renameText) }
                renaming = nil
            }
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let thread = deleting { delete(thread) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("This removes the chat and its messages from this device.")
        }
    }

    private func rows(_ items: [ThreadRecord]) -> some View {
        ForEach(items) { thread in
            Text(thread.title)
                .lineLimit(1)
                .tag(thread.id)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { deleting = thread } label: { Label("Delete", systemImage: "trash") }
                    Button { ThreadActions.togglePin(thread) } label: { pinLabel(thread) }.tint(.orange)
                }
                .contextMenu {
                    Button { beginRename(thread) } label: { Label("Rename", systemImage: "pencil") }
                    Button { ThreadActions.togglePin(thread) } label: { pinLabel(thread) }
                    Button(role: .destructive) { deleting = thread } label: { Label("Delete", systemImage: "trash") }
                }
        }
    }

    private func pinLabel(_ thread: ThreadRecord) -> some View {
        Label(thread.isPinned ? "Unpin" : "Pin", systemImage: thread.isPinned ? "pin.slash" : "pin")
    }

    private func beginRename(_ thread: ThreadRecord) {
        renameText = thread.title
        renaming = thread
    }

    private func delete(_ thread: ThreadRecord) {
        let id = thread.id
        ThreadActions.delete(thread, in: context)
        shell.threadDeleted(id)
    }
}

#Preview("Sidebar") {
    let container = try! ModelContainer.anyRouter(inMemory: true)
    for (i, title) in ["Trip to Lisbon", "Swift concurrency", "Recipe ideas"].enumerated() {
        let t = ThreadRecord(title: title, isPinned: i == 0)
        container.mainContext.insert(t)
    }
    return ThreadSidebar(isDrawer: true)
        .environment(ShellModel())
        .modelContainer(container)
}
