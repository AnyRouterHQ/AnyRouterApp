import SwiftData
import SwiftUI

/// Sidebar: a stock sidebar `List` with a search row that opens the full-screen search, a settings button and a
/// compose button in the bottom bar. On iPhone it fills the drawer, on iPad the split-view column.
struct ThreadSidebar: View {
    /// True when shown as a drawer over the chat (iPhone). Picking something then closes it.
    let isDrawer: Bool

    @Environment(ShellModel.self) private var shell
    @Query(sort: \ThreadRecord.updatedAt, order: .reverse) private var threads: [ThreadRecord]

    @State private var editing = ThreadEditing()

    private var sections: ThreadListLogic.Sections {
        ThreadListLogic.sections(from: threads)
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
            Button { shell.presentSearch() } label: {
                Label("Search chats", systemImage: "magnifyingglass").frame(minHeight: 44)
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("sidebar.search")
            if sections.isEmpty {
                Text("No chats yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
            if !sections.pinned.isEmpty { Section("Pinned") { rows(sections.pinned) } }
            if !sections.recent.isEmpty { Section("Recents") { rows(sections.recent) } }
        }
        .listStyle(.sidebar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // The logo mark alone; the app name is not repeated here.
                ARLogoMark(size: 26)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("AnyRouter")
                    .accessibilityIdentifier("sidebar.header")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { shell.presentSettings(closeSidebar: isDrawer) } label: {
                    Image(systemName: "gearshape").imageScale(.large).frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("sidebar.settings")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button { shell.newChat(closeSidebar: isDrawer) } label: {
                    Image(systemName: "square.and.pencil").imageScale(.large).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel("New chat")
                .accessibilityIdentifier("sidebar.compose")
            }
        }
        .threadEditingDialogs($editing)
    }

    private func rows(_ items: [ThreadRecord]) -> some View {
        ForEach(items) { thread in
            Text(thread.title)
                .lineLimit(1)
                .tag(thread.id)
                .threadActions(thread, editing: $editing)
        }
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
