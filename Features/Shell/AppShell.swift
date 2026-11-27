import SwiftData
import SwiftUI

/// Sidebar plus chat. iPhone: a wide drawer the chat slides away from. iPad: a persistent sidebar column.
struct AppShell: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @SceneStorage("shell.selectedThread") private var storedThread = ""

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if isRegular { PadShell() } else { PhoneShell() }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        // Form and page sizes only apply in a regular-width window. On iPhone and in a compact iPad window these are the usual sheets.
        .sheet(isPresented: Bindable(shell).isSettingsPresented) { SettingsScreen().presentationSizing(.form) }
        .sheet(isPresented: Bindable(shell).isHubPresented) { HubSheet().presentationSizing(.page) }
        .sheet(isPresented: Bindable(shell).isDecisionsPresented) { DecisionsSheet().presentationSizing(.page) }
        // Chat search is its own screen: full screen on iPhone, a page sheet in a regular-width window.
        .fullScreenCover(isPresented: searchBinding(whenRegular: false)) { ThreadSearchScreen() }
        .sheet(isPresented: searchBinding(whenRegular: true)) { ThreadSearchScreen().presentationSizing(.page) }
        // Only the iPhone drawer uses `isSidebarOpen`. It starts closed whenever the window becomes compact.
        .onChange(of: isRegular) { shell.isSidebarOpen = false }
        .onAppear { restoreSelection() }
        .onChange(of: shell.selectedThreadID) { _, id in storedThread = id?.uuidString ?? "" }
    }

    /// One of the two search presentations: the one that fits the window shows, the other stays closed.
    private func searchBinding(whenRegular: Bool) -> Binding<Bool> {
        Binding(
            get: { shell.isSearchPresented && isRegular == whenRegular },
            set: { if !$0 { shell.isSearchPresented = false } }
        )
    }

    /// Reopens the thread this scene showed before it was closed, unless the app was away longer than
    /// "Start a new chat after". The time away is read here, in the same step as the restore: a separate launch check
    /// could run first, forget the time away, and then this restore reopened the old thread.
    private func restoreSelection() {
        shell.launched(restoring: storedThreadIfItExists(), backgroundedAt: settings.lastBackgroundedAt,
                       now: .now, delay: settings.newChatDelay)
        settings.lastBackgroundedAt = nil
    }

    private func storedThreadIfItExists() -> UUID? {
        guard let id = UUID(uuidString: storedThread) else { return nil }
        var descriptor = FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0 ? id : nil
    }
}

/// A regular-width window: the system split view. The system toggles the sidebar from the toolbar.
private struct PadShell: View {
    @Environment(ShellModel.self) private var shell

    /// `.automatic` is the system's choice for the window: the sidebar beside the chat in landscape, tucked away in portrait.
    @State private var visibility = NavigationSplitViewVisibility.automatic
    @State private var isPortrait = false

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            ThreadSidebar(isDrawer: false)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            Detail()
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < $0.size.height } action: { isPortrait = $0 }
        // A toggle made in one shape of window is not carried into the other: turning the iPad gives the system default back.
        .onChange(of: isPortrait) { visibility = .automatic }
        // In portrait the sidebar floats over the chat, so picking a chat closes it.
        .onChange(of: shell.selectedThreadID) { if isPortrait { visibility = .detailOnly } }
        // View > Toggle Sidebar. `.automatic` shows the sidebar except in portrait.
        .onChange(of: shell.sidebarToggleRequest) {
            let showing = visibility == .all || visibility == .doubleColumn || (visibility == .automatic && !isPortrait)
            visibility = showing ? .detailOnly : .all
        }
    }
}

private struct PhoneShell: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Full screen width, measured on the container that ignores the safe area.
    @State private var screenWidth: CGFloat = 390
    /// Finger offset while a drag is tracked; the drawer follows it directly, without animation.
    @State private var dragX: CGFloat = 0
    /// nil until the first movement decides whether the drag belongs to the drawer.
    @State private var tracking: Bool?

    private var settle: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86)
    }

    var body: some View {
        let width = DrawerLogic.width(forScreen: screenWidth)
        let progress = DrawerLogic.progress(isOpen: shell.isSidebarOpen, drag: dragX, width: width)
        // The container fills the screen, status bar and home indicator included. The chat and the
        // sidebar are full-height siblings: the chat slides next to the sidebar and never covers it.
        // Their navigation stacks apply the real safe area to their own content.
        ZStack(alignment: .leading) {
            Color(.systemBackground)
            if reduceMotion {
                chat(progress: progress)
                sidebar(width: width).opacity(progress)
            } else {
                // Fully out of the tree while closed: accessibilityHidden alone left the List cells reachable.
                sidebar(width: width).opacity(progress > 0.001 ? 1 : 0)
                chat(progress: progress).offset(x: progress * width)
            }
        }
        .ignoresSafeArea(.container)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .contentShape(Rectangle())
        .simultaneousGesture(drag(width: width))
        .animation(settle, value: shell.isSidebarOpen)
        // Opening the drawer ends the composer's editing.
        .onChange(of: shell.isSidebarOpen) { _, open in if open { KeyboardDismissal.endEditing() } }
        // View > Toggle Sidebar from a hardware keyboard.
        .onChange(of: shell.sidebarToggleRequest) { setOpen(!shell.isSidebarOpen) }
    }

    private func sidebar(width: CGFloat) -> some View {
        ThreadSidebar(isDrawer: true)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .allowsHitTesting(shell.isSidebarOpen)
            .accessibilityHidden(!shell.isSidebarOpen)
    }

    private func chat(progress: CGFloat) -> some View {
        Detail()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .allowsHitTesting(!shell.isSidebarOpen)
            .accessibilityHidden(shell.isSidebarOpen)
            // Concentric with the display corners while the drawer is open or moving; no clip when closed.
            .clipShape(progress > 0.001 ? AnyShape(ConcentricRectangle()) : AnyShape(Rectangle()))
            .overlay {
                // A hairline along the edge that meets the sidebar, following the rounded corners.
                ConcentricRectangle()
                    .stroke(Color(.separator), lineWidth: 0.5)
                    .opacity(progress)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("main.container")
            // The container's accessibility frame ignores the drawer offset (a run measured {0,62,402,778} with the drawer
            // open), so it sat over the drawer's rows and gear in the tree. Out of the tree while the drawer is open.
            .accessibilityHidden(shell.isSidebarOpen)
            .overlay {
                // Closes the drawer on a tap on the visible strip of chat. Invisible: the chat is never dimmed.
                // A sibling of the container, not a child, so it stays reachable while the container is hidden.
                Button { setOpen(false) } label: { Color.clear.contentShape(.rect) }
                    .buttonStyle(.plain)
                    .allowsHitTesting(shell.isSidebarOpen)
                    .accessibilityLabel("Close sidebar")
                    .accessibilityHidden(!shell.isSidebarOpen)
            }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if tracking == nil {
                    tracking = DrawerLogic.tracks(startX: value.startLocation.x, translation: value.translation,
                                                  isOpen: shell.isSidebarOpen, width: width)
                }
                if tracking == true { dragX = value.translation.width }
            }
            .onEnded { value in
                defer { tracking = nil }
                guard tracking == true else { return }
                let open = DrawerLogic.shouldOpen(isOpen: shell.isSidebarOpen, predictedEnd: value.predictedEndTranslation.width, width: width)
                withAnimation(settle) {
                    shell.isSidebarOpen = open
                    dragX = 0
                }
            }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(settle) { shell.isSidebarOpen = open }
    }
}

private struct Detail: View {
    var body: some View {
        NavigationStack {
            ChatScreen()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.detail")
    }
}
