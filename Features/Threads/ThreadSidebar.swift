import SwiftData
import SwiftUI

/// Sidebar: a header row (logo, app name, search), then a plain list (Apps, pinned and recent chats) and a bottom bar
/// with Settings and New chat. On iPhone it fills the drawer, on iPad the split-view column. Everything starts on one
/// leading edge and trailing items end on one trailing edge, `margin` from the sides, as in a stock list.
struct ThreadSidebar: View {
    /// True when shown as a drawer over the chat (iPhone). Picking something then closes it.
    let isDrawer: Bool

    @Environment(ShellModel.self) private var shell
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Row and hit-area heights grow with Dynamic Type instead of clipping the text.
    @ScaledMetric(relativeTo: .body) private var rowHeight = ARTheme.controlSize
    @ScaledMetric(relativeTo: .body) private var controlSize = ARTheme.controlSize
    @ScaledMetric(relativeTo: .title3) private var logoSize: CGFloat = 22
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
            appsRow
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
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(.rect)
                    }
                    .accessibilityIdentifier("sidebar.viewall")
                }
                rows(sections.recent)
            }
        }
        .listStyle(.plain)
        // Rows set their own 44 pt; the section titles stay as short as their text.
        .environment(\.defaultMinListRowHeight, 0)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // A bar, not an inset, so the rows get the scroll edge effect under the header.
        .safeAreaBar(edge: .top, spacing: 8) { titleRow }
        // Hand-made, in a bar: as system bottom-bar items the toolbar drew a bare "+" for New chat (screenshots
        // 46140428971, 46145329030), and the operator keeps the gear and the "New chat" capsule.
        .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
        .threadEditingDialogs($editing)
    }

    /// The list's side margin: every row's text, the header and the bottom bar line up on it.
    fileprivate static let margin: CGFloat = 16

    private var titleRow: some View {
        HStack(spacing: 8) {
            ARLogoMark(size: logoSize).foregroundStyle(.primary).accessibilityHidden(true)
            Text("AnyRouter")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sidebar.header")
            Spacer()
            Button { shell.presentSearch() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("Search chats")
            .accessibilityIdentifier("sidebar.search")
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Self.margin)
    }

    /// Section titles are rows, not `Section` headers: a plain list puts about 22 pt above each header that SwiftUI
    /// cannot remove, and makes them sticky. 20 pt above, 6 pt below, the system header style.
    private func header<Trailing: View>(
        _ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        // An overlay centred on the title, same font, so its text sits on the title's baseline while its 44 pt target
        // reaches into the gaps above and below without making the title row taller. A negative padding kept the row
        // short but shrank the target itself to about 20 pt (accessibility audit: View all hit area).
        .overlay(alignment: .trailing) { trailing().font(.subheadline) }
        .listRowInsets(EdgeInsets(top: 20, leading: Self.margin, bottom: 6, trailing: Self.margin))
        .listRowSeparator(.hidden)
        .selectionDisabled()
    }

    /// Settings and New chat: sibling glass in one container, both `ARTheme.controlSize` tall (design review P3).
    private var bottomBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack {
                Button { shell.presentSettings(closeSidebar: isDrawer) } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .frame(width: controlSize, height: controlSize)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(.circle)
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
                        .frame(minHeight: controlSize)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .contentShape(.capsule)
                }
                .accessibilityIdentifier("sidebar.compose")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, Self.margin)
        .padding(.vertical, 8)
    }

    private var appsRow: some View {
        Button { shell.open(.apps, closeSidebar: isDrawer) } label: {
            Label("Apps", systemImage: "square.grid.2x2")
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: rowHeight)
        }
        .foregroundStyle(.primary)
        .rowInsets()
        .accessibilityIdentifier("sidebar-apps")
    }

    private func rows(_ items: [ThreadRecord]) -> some View {
        ForEach(items) { thread in
            Text(thread.title)
                // One line at the default size; above it the title wraps instead of being cut (accessibility audit, drawer).
                .lineLimit(typeSize > .large ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: rowHeight)
                .rowInsets()
                .tag(thread.id)
                // A plain list does not mark the open chat on iPhone, so the drawer paints the system fill inside the row's
                // margins; the iPad column keeps the list's own selection.
                .listRowBackground(
                    isDrawer && thread.id == shell.selectedThreadID
                        ? Color(.quaternarySystemFill).clipShape(.rect(cornerRadius: 10, style: .continuous)).padding(.horizontal, 8)
                        : nil
                )
                .threadActions(thread, editing: $editing)
        }
    }
}

private extension View {
    /// Row text on the list's margin; the open chat's highlight sits 8 pt inside the drawer edges.
    func rowInsets() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: ThreadSidebar.margin, bottom: 0, trailing: ThreadSidebar.margin))
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
