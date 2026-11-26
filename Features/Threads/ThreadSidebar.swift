import SwiftData
import SwiftUI

/// Atomic's left sidebar: brand, new chat, search, pinned and recent threads, hub and settings links.
struct ThreadSidebar: View {
    /// True when shown as a drawer over the chat (iPhone). Picking something then closes it.
    let isDrawer: Bool

    @Environment(ShellModel.self) private var shell
    @Environment(\.modelContext) private var context
    @Query(sort: \ThreadRecord.updatedAt, order: .reverse) private var threads: [ThreadRecord]

    @State private var query = ""
    @State private var renaming: ThreadRecord?
    @State private var renameText = ""
    @State private var deleting: ThreadRecord?

    private var sections: ThreadListLogic.Sections {
        ThreadListLogic.sections(from: threads, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ARSearchField(text: $query, prompt: "Search chats")
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            list
            footer
        }
        .background(ARColor.sidebar.ignoresSafeArea())
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let thread = renaming {
                    thread.title = ThreadListLogic.renamed(renameText, current: thread.title)
                }
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
            ARLogoMark(size: 24).foregroundStyle(ARColor.foreground)
            Text("AnyRouter").font(.system(size: 18, weight: .semibold)).foregroundStyle(ARColor.foreground)
            Spacer()
            ARIconButton(systemName: "square.and.pencil", label: "New chat") {
                shell.newChat(closeSidebar: isDrawer)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
                Section { rows(sections.pinned) } header: { ARSectionTitle("Pinned") }
            }
            if !sections.recent.isEmpty {
                Section { rows(sections.recent) } header: { ARSectionTitle("Chats") }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func rows(_ items: [ThreadRecord]) -> some View {
        ForEach(items) { thread in
            ThreadRow(thread: thread, isSelected: shell.selectedThreadID == thread.id)
                .contentShape(Rectangle())
                .onTapGesture { shell.select(threadID: thread.id, closeSidebar: isDrawer) }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleting = thread } label: { Label("Delete", systemImage: "trash") }
                    Button { beginRename(thread) } label: { Label("Rename", systemImage: "pencil") }.tint(.gray)
                }
                .swipeActions(edge: .leading) {
                    Button { thread.isPinned.toggle() } label: {
                        Label(thread.isPinned ? "Unpin" : "Pin", systemImage: thread.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(ARColor.accent)
                }
                .contextMenu {
                    Button { thread.isPinned.toggle() } label: {
                        Label(thread.isPinned ? "Unpin" : "Pin", systemImage: thread.isPinned ? "pin.slash" : "pin")
                    }
                    Button { beginRename(thread) } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = thread } label: { Label("Delete", systemImage: "trash") }
                }
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            Divider().overlay(ARColor.border)
            footerRow("Browse Models", systemImage: "square.stack.3d.up", route: .hub)
            footerRow("Settings", systemImage: "gearshape", route: .settings)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func footerRow(_ title: String, systemImage: String, route: ShellModel.Route) -> some View {
        Button { shell.open(route, closeSidebar: isDrawer) } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage).frame(width: 22)
                Text(title).font(.arBase)
                Spacer()
            }
            .foregroundStyle(ARColor.foreground)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(shell.route == route ? ARColor.sidebarAccent : .clear,
                        in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func beginRename(_ thread: ThreadRecord) {
        renameText = thread.title
        renaming = thread
    }

    private func delete(_ thread: ThreadRecord) {
        let id = thread.id
        context.delete(thread)
        shell.threadDeleted(id)
    }
}

private struct ThreadRow: View {
    let thread: ThreadRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if thread.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(ARColor.mutedForeground)
            }
            Text(thread.title)
                .font(.arBase)
                .foregroundStyle(ARColor.foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(isSelected ? ARColor.sidebarAccent : .clear,
                    in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
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
