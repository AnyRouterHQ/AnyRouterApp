import SwiftData
import SwiftUI

/// Sidebar plus chat. iPhone: a wide drawer the chat slides away from. iPad: a persistent sidebar column.
struct AppShell: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context
    @SceneStorage("shell.selectedThread") private var storedThread = ""

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if isRegular { PadShell() } else { PhoneShell() }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .sheet(isPresented: Bindable(shell).isSettingsPresented) { SettingsScreen() }
        .sheet(isPresented: Bindable(shell).isHubPresented) { HubSheet() }
        .sheet(isPresented: Bindable(shell).isDecisionsPresented) { DecisionsSheet() }
        .onChange(of: isRegular, initial: true) { _, regular in
            shell.isSidebarOpen = regular
        }
        .onAppear { restoreSelection() }
        .onChange(of: shell.selectedThreadID) { _, id in storedThread = id?.uuidString ?? "" }
    }

    /// Reopens the thread this scene showed before it was closed, if it still exists.
    private func restoreSelection() {
        guard shell.selectedThreadID == nil, let id = UUID(uuidString: storedThread) else { return }
        var descriptor = FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if ((try? context.fetchCount(descriptor)) ?? 0) > 0 { shell.selectedThreadID = id }
    }
}

private struct PadShell: View {
    @Environment(ShellModel.self) private var shell

    private var visibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { shell.isSidebarOpen ? .all : .detailOnly },
            set: { shell.isSidebarOpen = $0 != .detailOnly }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: visibility) {
            ThreadSidebar(isDrawer: false)
                .navigationSplitViewColumnWidth(min: 320, ideal: 320, max: 320)
        } detail: {
            Detail()
        }
        .navigationSplitViewStyle(.balanced)
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
                chat(progress: progress, width: width)
                sidebar(width: width).opacity(progress)
            } else {
                sidebar(width: width)
                chat(progress: progress, width: width).offset(x: progress * width)
            }
        }
        .ignoresSafeArea(.container)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .contentShape(Rectangle())
        .simultaneousGesture(drag(width: width))
        .animation(settle, value: shell.isSidebarOpen)
        // The keyboard belongs to whichever side the user is typing in. Opening the drawer ends the
        // composer's editing; the search field in the sidebar only takes focus when tapped.
        .onChange(of: shell.isSidebarOpen) { _, open in if open { KeyboardDismissal.endEditing() } }
    }

    private func sidebar(width: CGFloat) -> some View {
        ThreadSidebar(isDrawer: true)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .allowsHitTesting(shell.isSidebarOpen)
            .accessibilityHidden(!shell.isSidebarOpen)
    }

    private func chat(progress: CGFloat, width: CGFloat) -> some View {
        Detail()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            // While the drawer is open the keyboard (the sidebar search) never resizes the chat.
            .ignoresSafeArea(.keyboard, edges: shell.isSidebarOpen ? .bottom : [])
            .allowsHitTesting(!shell.isSidebarOpen)
            .accessibilityHidden(shell.isSidebarOpen)
            .overlay {
                // Dims the chat and closes the drawer on tap. It covers the whole chat, edge to edge.
                Button { setOpen(false) } label: { Color.black.opacity(0.2 * progress) }
                    .buttonStyle(.plain)
                    .allowsHitTesting(shell.isSidebarOpen)
                    .accessibilityLabel("Close sidebar")
                    .accessibilityHidden(!shell.isSidebarOpen)
            }
            // Concentric with the display corners while the drawer is open or moving; no clip when closed.
            .clipShape(progress > 0.001 ? AnyShape(ConcentricRectangle()) : AnyShape(Rectangle()))
            .overlay(alignment: .leading) {
                // A soft edge on the side that meets the sidebar.
                LinearGradient(colors: [.black.opacity(0.14 * progress), .clear], startPoint: .trailing, endPoint: .leading)
                    .frame(width: 12)
                    .offset(x: -12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("main.container")
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
    }
}
