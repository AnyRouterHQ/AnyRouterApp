import SwiftData
import SwiftUI

/// Chat page: toolbar (menu, model pill, new chat), message list and a glass composer. Rebuilds its view model when the thread changes.
struct ChatScreen: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.modelContext) private var context
    @Environment(EngineRegistry.self) private var registry
    @Environment(AppSettings.self) private var settings
    @Environment(ModelStore.self) private var models
    @Environment(AppState.self) private var app

    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var chat: ChatViewModel?
    @State private var showsPicker = false

    var body: some View {
        Group {
            if let chat {
                ChatContent(chat: chat, hasModel: models.selected != nil, presets: app.presets)
            } else {
                Color.clear
            }
        }
        .toolbar {
            // The regular-width split view supplies its own sidebar toggle when the column is collapsed.
            if sizeClass == .compact {
                ToolbarItem(placement: .topBarLeading) {
                    Button { shell.toggleSidebar() } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("Menu")
                }
            }
            ToolbarItem(placement: .principal) {
                ModelPill { showsPicker = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { shell.newChat(closeSidebar: false) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New chat")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: shell.selectedThreadID) { prepare() }
        .sheet(isPresented: $showsPicker) {
            ModelPickerSheet()
        }
    }

    /// Keeps the current model when it already shows the selected thread (a first send creates the thread itself).
    private func prepare() {
        if let chat, chat.thread?.id == shell.selectedThreadID { return }
        chat?.stop()
        let thread = shell.selectedThreadID.flatMap(fetchThread)
        let model = ChatViewModel(thread: thread, context: context, registry: registry,
                                  settings: settings, models: models)
        model.onThreadCreated = { [shell] id in shell.selectedThreadID = id }
        if let modelID = thread?.modelID { models.select(modelID: modelID) }
        chat = model
    }

    private func fetchThread(_ id: UUID) -> ThreadRecord? {
        var descriptor = FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

private struct ChatContent: View {
    @Bindable var chat: ChatViewModel
    let hasModel: Bool
    let presets: PresetStore
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if chat.messages.isEmpty {
                emptyState
            } else {
                messageList
            }
        }
        // The composer floats on glass over the list, so messages scroll beneath it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(model: chat, hasModel: hasModel, presets: presets, focused: $composerFocused)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            ARLogoMark(size: 48).foregroundStyle(ARColor.foreground)
            Text("How can I help?").font(.arTitle).foregroundStyle(ARColor.foreground)
            Spacer()
            PresetSuggestions(store: presets, onPick: { chat.usePreset($0) }, onSend: { chat.sendNow($0) })
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
    }

    private var messageList: some View {
        let messages = chat.messages
        let lastID = messages.last?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(messages) { message in
                        MessageRow(
                            message: message,
                            isStreamingThis: chat.isStreaming && message.id == lastID,
                            showsRegenerate: message.id == lastID && chat.canRegenerate,
                            onRegenerate: { chat.regenerate() }
                        )
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: ARTheme.contentMaxWidth)
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: messages.last?.content.count) {
                if chat.isStreaming { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

#Preview("Chat") {
    let container = try! ModelContainer.anyRouter(inMemory: true)
    let state = AppState()
    return ChatScreen()
        .environment(ShellModel())
        .environment(state.registry)
        .environment(state.settings)
        .environment(state.models)
        .environment(state)
        .modelContainer(container)
        .background(ARColor.background)
}
