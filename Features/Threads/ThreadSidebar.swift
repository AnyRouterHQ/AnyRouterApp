import SwiftData
import SwiftUI

/// Sidebar: the app name over a plain list (search, pinned and recent chats, more places) and a bottom bar with
/// Settings and New chat. On iPhone it fills the drawer, on iPad the split-view column.
struct ThreadSidebar: View {
    /// True when shown as a drawer over the chat (iPhone). Picking something then closes it.
    let isDrawer: Bool

    @Environment(ShellModel.self) private var shell
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Row and hit-area heights grow with Dynamic Type instead of clipping the text.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var searchHeight: CGFloat = 36
    /// Gear and New chat: one 40 pt glass shape inside a 44 pt hit area.
    @ScaledMetric(relativeTo: .body) private var barButtonHeight: CGFloat = 40
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
            // A quiet capsule (36 pt, scaled) inside a 44 pt hit area: it points at the search, it is not the field.
            Button { shell.presentSearch() } label: {
                Label("Search chats", systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: searchHeight, alignment: .leading)
                    .background(Color(.quaternarySystemFill), in: .capsule)
                    .frame(minHeight: rowHeight)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .rowInsets()
            .accessibilityIdentifier("sidebar.search")
            if sections.isEmpty {
                Text("No chats yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            }
            if !sections.pinned.isEmpty {
                header("Pinned")
                rows(sections.pinned)
            }
            if !sections.recent.isEmpty {
                header("Recents") {
                    Button { shell.presentSearch() } label: {
                        HStack(spacing: 4) { Text("View all"); Image(systemName: "chevron.right").imageScale(.small) }
                            .frame(minWidth: 44, minHeight: rowHeight)
                            .contentShape(.rect)
                    }
                    .accessibilityIdentifier("sidebar.viewall")
                }
                rows(sections.recent)
            }
            header("More")
            moreRows
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, rowHeight)
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

    /// Section titles are rows, not `Section` headers: a plain list puts about 22 pt above each header that SwiftUI
    /// cannot remove, which spread the drawer out.
    private func header<Trailing: View>(
        _ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack {
            // Primary, not secondary: the accessibility audit reads secondary at this size as "contrast nearly passed".
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing().font(.subheadline)
        }
        .padding(.horizontal, 8)
        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 0, trailing: 12))
        .listRowSeparator(.hidden)
        .selectionDisabled()
    }

    private var bottomBar: some View {
        GlassEffectContainer {
            HStack {
                Button { shell.presentSettings(closeSidebar: isDrawer) } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .frame(width: barButtonHeight, height: barButtonHeight)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .barHitArea()
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("sidebar.settings")
                Spacer()
                Button { shell.newChat(closeSidebar: isDrawer) } label: {
                    Label("New chat", systemImage: "plus")
                        .font(.body.weight(.medium))
                        // Never cut: at large text the capsule grows instead (the audit flagged "New chat" clipped).
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .frame(minHeight: barButtonHeight)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .barHitArea()
                }
                .accessibilityIdentifier("sidebar.compose")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var moreRows: some View {
        Button { shell.open(.decisions, closeSidebar: isDrawer) } label: {
            Label("Decisions", systemImage: "checklist")
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: rowHeight)
        }
        .foregroundStyle(.primary)
        .rowInsets()
        .accessibilityIdentifier("sidebar-decisions")
    }

    private func rows(_ items: [ThreadRecord]) -> some View {
        ForEach(items) { thread in
            Text(thread.title)
                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: rowHeight)
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
    /// The 40 pt glass shape keeps a 44 pt tap target (HIG minimum, checked by the accessibility audit).
    func barHitArea() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(.rect)
    }

    /// Rows sit 12 pt from the edges so the highlight of the open chat has room; the content keeps the 20 pt of the title.
    func rowInsets() -> some View {
        padding(.horizontal, 8)
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            .listRowSeparator(.hidden)
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
