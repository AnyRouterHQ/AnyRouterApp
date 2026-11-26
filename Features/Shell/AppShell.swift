import SwiftUI

/// Sidebar plus chat. iPhone: a wide drawer the chat slides away from. iPad: a persistent sidebar column.
struct AppShell: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if isRegular { PadShell() } else { PhoneShell() }
        }
        .background(ARColor.background.ignoresSafeArea())
        .sheet(isPresented: Bindable(shell).isSettingsPresented) { SettingsScreen() }
        .onChange(of: isRegular, initial: true) { _, regular in
            shell.isSidebarOpen = regular
        }
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
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            Detail().toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct PhoneShell: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Finger offset while a drag is tracked; the drawer follows it directly, without animation.
    @State private var dragX: CGFloat = 0
    /// nil until the first movement decides whether the drag belongs to the drawer.
    @State private var tracking: Bool?

    private var settle: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.86)
    }

    var body: some View {
        GeometryReader { geo in
            let width = DrawerLogic.width(forScreen: geo.size.width)
            let progress = DrawerLogic.progress(isOpen: shell.isSidebarOpen, drag: dragX, width: width)
            ZStack(alignment: .leading) {
                if reduceMotion {
                    chat(progress: progress, shifted: false, width: geo.size.width)
                    ThreadSidebar(isDrawer: true)
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .opacity(progress)
                        .allowsHitTesting(shell.isSidebarOpen)
                        .accessibilityHidden(!shell.isSidebarOpen)
                } else {
                    ThreadSidebar(isDrawer: true)
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(!shell.isSidebarOpen)
                    chat(progress: progress, shifted: true, width: geo.size.width)
                        .offset(x: progress * width)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(drag(width: width))
            .animation(settle, value: shell.isSidebarOpen)
        }
    }

    private func chat(progress: CGFloat, shifted: Bool, width: CGFloat) -> some View {
        Detail()
            .frame(width: width)
            .background(ARColor.background)
            .allowsHitTesting(!shell.isSidebarOpen)
            .accessibilityHidden(shell.isSidebarOpen)
            .overlay {
                Color.black.opacity(0.22 * progress)
                    .allowsHitTesting(shell.isSidebarOpen)
                    .onTapGesture { setOpen(false) }
                    .accessibilityLabel("Close sidebar")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHidden(!shell.isSidebarOpen)
            }
            .clipShape(RoundedRectangle(cornerRadius: shifted ? 28 * progress : 0, style: .continuous))
            .shadow(color: .black.opacity(shifted ? 0.18 * progress : 0), radius: 18)
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
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Group {
            switch shell.route {
            case .chat: ChatScreen()
            case .hub: HubScreen()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
