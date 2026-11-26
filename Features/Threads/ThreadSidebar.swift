import SwiftData
import SwiftUI

/// Sidebar: the app name over a plain list (search, pinned and recent chats, more places) and a bottom bar with
/// Settings and New chat. On iPhone it fills the drawer, on iPad the split-view column.
struct ThreadSidebar: View {
    /// True when shown as a drawer over the chat (iPhone). Picking something then closes it.
    let isDrawer: Bool

    @Environment(ShellModel.self) private var shell
    @Environment(\.dynamicTypeSize) private var typeSize
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
        // The iPad column already sits in a navigation context; the drawer needs its own. Its bar stays hidden:
        // the title row below replaces it. The iPad column keeps its bar for the system sidebar toggle.
        if isDrawer {
            NavigationStack { content.toolbar(.hidden, for: .navigationBar) }
        } else {
            content
        }
    }

    private var content: some View {
        List(selection: selection) {
            // A quiet 36 pt capsule inside a 44 pt hit area: it points at the search, it is not the field.
            Button { shell.presentSearch() } label: {
                Label("Search chats", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .background(.quaternary, in: .capsule)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .rowInsets()
            .accessibilityIdentifier("sidebar.search")
            if sections.isEmpty {
                Text("No chats yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            if !sections.pinned.isEmpty { Section { rows(sections.pinned) } header: { header("Pinned") } }
            if !sections.recent.isEmpty {
                Section { rows(sections.recent) } header: {
                    header("Recents") {
                        Button { shell.presentSearch() } label: {
                            HStack(spacing: 4) { Text("View all"); Image(systemName: "chevron.right").imageScale(.small) }
                                .frame(minHeight: 44)
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("sidebar.viewall")
                    }
                }
            }
            Section { moreRows } header: { header("More") }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .safeAreaInset(edge: .top, spacing: 0) { titleRow }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .threadEditingDialogs($editing)
    }

    private var titleRow: some View {
        HStack {
            Text("AnyRouter")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sidebar.header")
            Spacer()
            ARLogoMark(size: 28).foregroundStyle(.primary).accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var bottomBar: some View {
        HStack {
            Button { shell.presentSettings(closeSidebar: isDrawer) } label: {
                Image(systemName: "gearshape").imageScale(.large).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("sidebar.settings")
            Spacer()
            Button { shell.newChat(closeSidebar: isDrawer) } label: {
                Label("New chat", systemImage: "plus").frame(minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .accessibilityIdentifier("sidebar.compose")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    /// Section titles in the quiet secondary style, with an optional trailing control.
    private func header(_ title: LocalizedStringKey) -> some View {
        header(title) { EmptyView() }
    }

    private func header(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(title)
            Spacer()
            trailing()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .textCase(nil)
    }

    private var moreRows: some View {
        Button { shell.open(.decisions, closeSidebar: isDrawer) } label: {
            Label("Decisions", systemImage: "checklist").frame(minHeight: 44)
        }
        .foregroundStyle(.primary)
        .rowInsets()
        .accessibilityIdentifier("sidebar-decisions")
    }

    private func rows(_ items: [ThreadRecord]) -> some View {
        ForEach(items) { thread in
            Label(thread.title, systemImage: "bubble.left")
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .frame(minHeight: 44)
                .rowInsets()
                .tag(thread.id)
                // A plain list does not mark the open chat on iPhone, so the row paints its own highlight.
                .listRowBackground(
                    thread.id == shell.selectedThreadID
                        ? Color(.quaternarySystemFill).clipShape(.rect(cornerRadius: 12)) : nil
                )
                .threadActions(thread, editing: $editing)
        }
    }
}

private extension View {
    /// Rows sit 12 pt from the edges so the highlight of the open chat has room; the content keeps the 20 pt of the title.
    func rowInsets() -> some View {
        padding(.horizontal, 8).listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
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
