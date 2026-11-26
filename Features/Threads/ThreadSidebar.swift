import SwiftData
import SwiftUI

/// Sidebar: brand and settings on top, pinned and recent chats, search and compose at the bottom.
struct ThreadSidebar: View {
    /// True when shown as a drawer over the chat (iPhone). Picking something then closes it.
    let isDrawer: Bool

    @Environment(ShellModel.self) private var shell
    @Environment(\.modelContext) private var context
    @Query(sort: \ThreadRecord.updatedAt, order: .reverse) private var threads: [ThreadRecord]

    @State private var query = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    @State private var renaming: ThreadRecord?
    @State private var renameText = ""
    @State private var deleting: ThreadRecord?

    private var sections: ThreadListLogic.Sections {
        ThreadListLogic.sections(from: threads, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            footer
        }
        .background(ARColor.sidebar.ignoresSafeArea())
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

    private var header: some View {
        HStack(spacing: 10) {
            ARLogoMark(size: 30).foregroundStyle(ARColor.foreground)
            Text("AnyRouter")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(ARColor.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            ARIconButton(systemName: "gearshape", label: "Settings") {
                shell.presentSettings(closeSidebar: isDrawer)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var list: some View {
        List {
            if sections.isEmpty {
                Text(query.isEmpty ? "No chats yet" : "No matching chats")
                    .font(.arSM)
                    .foregroundStyle(ARColor.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if !sections.pinned.isEmpty {
                Section { rows(sections.pinned) } header: { sectionTitle("Pinned") }
            }
            if !sections.recent.isEmpty {
                Section { rows(sections.recent) } header: { sectionTitle("Recents") }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func sectionTitle(_ text: String) -> some View {
        ARSectionTitle(text).padding(.horizontal, 8).textCase(nil)
    }

    private func rows(_ items: [ThreadRecord]) -> some View {
        ForEach(items) { thread in
            Button { shell.select(threadID: thread.id, closeSidebar: isDrawer) } label: {
                ThreadRow(title: thread.title, isSelected: shell.selectedThreadID == thread.id)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { deleting = thread } label: { Label("Delete", systemImage: "trash") }
                Button { ThreadActions.togglePin(thread) } label: { pinLabel(thread) }.tint(ARColor.accent)
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

    private var footer: some View {
        HStack(spacing: 12) {
            if isSearching {
                searchField
            } else {
                ARIconButton(systemName: "magnifyingglass", label: "Search chats") { setSearching(true) }
                Spacer()
            }
            Button { shell.newChat(closeSidebar: isDrawer) } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ARColor.primaryForeground)
                    .frame(width: 52, height: 52)
                    .background(ARColor.primary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New chat")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(ARColor.mutedForeground)
            TextField("Search chats", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            Button { setSearching(false) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(ARColor.mutedForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(ARColor.card, in: Capsule())
        .overlay(Capsule().strokeBorder(ARColor.border, lineWidth: 1))
    }

    private func setSearching(_ on: Bool) {
        withAnimation(.easeOut(duration: 0.15)) {
            isSearching = on
            if !on { query = "" }
        }
        searchFocused = on
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

private struct ThreadRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 17))
            .foregroundStyle(ARColor.foreground)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(isSelected ? ARColor.sidebarAccent : .clear,
                        in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
            .contentShape(Rectangle())
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
