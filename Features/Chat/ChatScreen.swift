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

    var body: some View {
        Group {
            if let chat {
                ChatContent(chat: chat, presets: app.presets,
                            subtitle: HomeLogic.subtitle(for: chat.model),
                            showsDetails: settings.showResponseDetails)
            } else {
                Color.clear
            }
        }
        .toolbar {
            // The regular-width split view supplies its own sidebar toggle when the column is collapsed.
            if sizeClass == .compact {
                ToolbarItem(placement: .topBarLeading) {
                    Button { shell.toggleSidebar() } label: { Image(systemName: "line.3.horizontal") }
                        .tint(.primary)
                        .accessibilityLabel("Menu")
                }
            }
            ToolbarItem(placement: .principal) {
                ModelPill(model: chat?.model, isLoading: models.isLoading) { shell.isModelPickerPresented = true }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                MemoryMenu()
                Button { shell.newChat(closeSidebar: false) } label: { Image(systemName: "square.and.pencil") }
                    .tint(.primary)
                    .accessibilityLabel("New chat")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background { if chat?.messages.isEmpty ?? true { ARHomeBackground().transition(.opacity) } }
        .animation(.easeInOut(duration: 0.3), value: chat?.messages.isEmpty)
        .task(id: shell.selectedThreadID) { prepare() }
        .sheet(isPresented: Bindable(shell).isModelPickerPresented) {
            ModelPickerSheet(currentID: chat?.model?.id) { chat?.choose($0) }
        }
        .toolApprovalDialog(app.toolApprovals)
    }

    /// Keeps the current model when it already shows the selected thread (a first send creates the thread itself).
    private func prepare() {
        if let chat, chat.thread?.id == shell.selectedThreadID { return }
        chat?.stop()
        let thread = shell.selectedThreadID.flatMap(fetchThread)
        let model = ChatViewModel(thread: thread, context: context, registry: registry,
                                  settings: settings, models: models,
                                  toolHost: { [app] attachments in
                                      app.tools.makeHost(approver: app.toolApprovals, attachments: attachments)
                                  })
        model.onThreadCreated = { [shell] id in shell.selectedThreadID = id }
        if DemoData.attachesSampleFile, thread == nil { model.attachFiles([DemoData.sampleAttachmentURL()]) }
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
    let presets: PresetStore
    let subtitle: String
    let showsDetails: Bool
    @FocusState private var composerFocused: Bool
    /// A tapped-in tip that replaces the model subtitle until the chat changes.
    @State private var tip: String?
    @State private var position = ScrollPosition(edge: .bottom)
    /// The list follows the reply while true (see `ScrollFollow`).
    @State private var following = true
    @State private var nearBottom = true

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
            Composer(model: chat, hasModel: chat.model != nil, presets: presets, focused: $composerFocused)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            ARLogoMark(size: 56)
            // A hidden gem: tapping the greeting swaps the line below for a tip. Not announced as a button.
            Button { tip = HomeTips.next(after: tip ?? subtitle) } label: {
                Text(HomeLogic.greeting)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows a tip")
            .accessibilityIdentifier("home.greeting")
            HStack(spacing: 6) {
                if tip == nil, let model = chat.model { ModelLogo(brand: ModelBrand.resolve(model), size: 15) }
                Text(tip ?? subtitle)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: tip)
            .accessibilityIdentifier("home.subtitle")
            Spacer()
            PresetSuggestions(store: presets, onPick: { chat.usePreset($0) }, onSend: { chat.sendNow($0) })
                .padding(.bottom, 8)
        }
        .padding(.horizontal, ARTheme.pagePadding)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: tip)
    }

    private var messageList: some View {
        let messages = chat.messages
        let lastID = messages.last?.id
        let switchNotes = SwitchNotes.make(messages)
        return ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(messages) { message in
                    MessageRow(
                        message: message,
                        isStreamingThis: chat.isStreaming && message.id == lastID,
                        showsRegenerate: message.id == lastID && chat.canRegenerate,
                        onRegenerate: { chat.regenerate() },
                        switchNote: switchNotes[message.id],
                        showsDetails: showsDetails,
                        loadingModelName: message.id == lastID ? chat.loadingModelName : nil
                    )
                }
            }
            .frame(maxWidth: ARTheme.contentMaxWidth)
            .padding(.horizontal, ARTheme.pagePadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            ScrollFollow.isNearBottom(
                offset: geometry.contentOffset.y, container: geometry.containerSize.height,
                content: geometry.contentSize.height, bottomInset: geometry.contentInsets.bottom)
        } action: { _, near in
            nearBottom = near
        }
        .onScrollPhaseChange { old, new in
            following = ScrollFollow.following(from: old, to: new, nearBottom: nearBottom, was: following)
        }
        // A new message is the reader's own send or a regenerate: always show it.
        .onChange(of: messages.count) {
            following = true
            position.scrollTo(edge: .bottom)
        }
        .onChange(of: messages.last?.toolTraceData) { if following { position.scrollTo(edge: .bottom) } }
        .onChange(of: messages.last?.content.count) { if following { position.scrollTo(edge: .bottom) } }
        .overlay(alignment: .bottom) {
            if !following {
                Button {
                    following = true
                    position.scrollTo(edge: .bottom)
                } label: {
                    Label("Jump to latest", systemImage: "arrow.down").labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: following)
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
}
