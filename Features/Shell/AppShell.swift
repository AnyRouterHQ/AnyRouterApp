import SwiftUI

/// Atomic's mobile layout: a sidebar drawer over the chat on iPhone, a persistent sidebar on iPad.
struct AppShell: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if isRegular {
                HStack(spacing: 0) {
                    if shell.isSidebarOpen {
                        ThreadSidebar(isDrawer: false)
                            .frame(width: ARTheme.sidebarWidth)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(ARColor.border).frame(width: 1)
                            }
                            .transition(.move(edge: .leading))
                    }
                    Detail()
                }
            } else {
                ZStack(alignment: .leading) {
                    Detail()
                    if shell.isSidebarOpen {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture { shell.isSidebarOpen = false }
                            .transition(.opacity)
                        ThreadSidebar(isDrawer: true)
                            .frame(width: min(ARTheme.sidebarWidth, 340))
                            .frame(maxHeight: .infinity)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(ARColor.border).frame(width: 1)
                            }
                            .transition(.move(edge: .leading))
                            .gesture(
                                DragGesture().onEnded { value in
                                    if value.translation.width < -60 { shell.isSidebarOpen = false }
                                }
                            )
                    }
                }
            }
        }
        .background(ARColor.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.22), value: shell.isSidebarOpen)
        .onChange(of: isRegular, initial: true) { _, regular in
            shell.isSidebarOpen = regular
        }
    }
}

private struct Detail: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        Group {
            switch shell.route {
            case .chat: ChatScreen()
            case .hub: HubPlaceholder()
            case .settings: SettingsPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HubPlaceholder: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(spacing: 0) {
            ARPageHeader(title: "Browse Models") { shell.open(.chat, closeSidebar: false) }
            ARComingSoon(title: "Browse Models", systemImage: "square.stack.3d.up")
        }
    }
}

private struct SettingsPlaceholder: View {
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(spacing: 0) {
            ARPageHeader(title: "Settings") { shell.open(.chat, closeSidebar: false) }
            ARComingSoon(title: "Settings", systemImage: "gearshape")
        }
    }
}
