import SwiftData
import SwiftUI

/// Chat page: two system toolbar buttons around the model title, a message list that runs under both bars, and a glass
/// composer. Rebuilds its view model when the thread changes.
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
                        .accessibilityLabel("Menu")
                }
            }
            ToolbarItem(placement: .principal) {
                ModelTitle(name: chat?.model?.shortName, isLoading: models.isLoading) { shell.isModelPickerPresented = true }
                    // A popover under the title on iPad. On iPhone and in a compact iPad window the system turns it into the sheet.
                    .popover(isPresented: Bindable(shell).isModelPickerPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        ModelPickerSheet(currentID: chat?.model?.id) { chat?.choose($0) }
                            .frame(minWidth: sizeClass == .regular ? 400 : nil, idealWidth: sizeClass == .regular ? 440 : nil,
                                   minHeight: sizeClass == .regular ? 520 : nil, idealHeight: sizeClass == .regular ? 640 : nil)
                    }
            }
            // The title floats on the content; the system must not wrap it in a glass capsule like the two buttons.
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button { shell.newChat(closeSidebar: false) } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background { if chat?.messages.isEmpty ?? true { ARHomeBackground().transition(.opacity) } }
        .animation(.easeInOut(duration: 0.3), value: chat?.messages.isEmpty)
        .task(id: shell.selectedThreadID) {
            prepare()
            applyInbound()
        }
        // On a window that already shows the fresh chat the task above does not run again.
        .onChange(of: shell.inbound?.id) { applyInbound() }
        .toolApprovalDialog(app.toolApprovals)
    }

    /// Keeps the current model when it already shows the selected thread (a first send creates the thread itself).
    private func prepare() {
        if let chat, chat.thread?.id == shell.selectedThreadID { return }
        chat?.stop()
        let thread = shell.selectedThreadID.flatMap(fetchThread)
        let model = ChatViewModel(thread: thread, context: context, registry: registry,
                                  settings: settings, models: models,
                                  toolHost: { [app] context in
                                      app.tools.makeHost(approver: app.toolApprovals, context: context)
                                  },
                                  isOnline: { [app] in app.network.isOnline },
                                  skipsToolsOffline: { [app] in app.tools.skipsOffline($0) })
        model.onThreadCreated = { [shell] id in shell.selectedThreadID = id }
        if DemoData.attachesSampleFile, thread == nil { model.attachFiles([DemoData.sampleAttachmentURL()]) }
        chat = model
    }

    /// An outside request lands in a fresh chat only. While the old thread is still showing, the task above applies
    /// it once `prepare()` has swapped the chat.
    private func applyInbound() {
        guard let chat, chat.thread == nil, let request = shell.takeInbound() else { return }
        chat.start(request, preset: request.presetID.flatMap { app.presets.preset(id: $0) })
    }

    private func fetchThread(_ id: UUID) -> ThreadRecord? {
        var descriptor = FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

private struct ChatContent: View {
    @Environment(AppState.self) private var app
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
    @ScaledMetric(relativeTo: .subheadline) private var greetingLogoSize: CGFloat = 15

    var body: some View {
        Group {
            if chat.messages.isEmpty {
                emptyState
            } else {
                messageList
            }
        }
        // The composer floats on glass over the list. As a bar (not a plain inset) it also gets the system's scroll
        // edge effect, so messages blur and fade beneath it like they do under the top bar.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Composer(model: chat, hasModel: chat.model != nil, presets: presets, focused: $composerFocused)
        }
        .refreshesMemory(app.memory)
        // A new reply cuts off the voice of the last one; "Read replies aloud" then follows the new reply as it arrives.
        .onChange(of: chat.isStreaming) { _, streaming in
            if streaming { app.speaker.stop() }
            followReply()
        }
        .onChange(of: chat.messages.last?.content.count) { followReply() }
        .onDisappear { app.speaker.stop() }
        // Text read from a photo waits here until the user picks what to do with it.
        .sheet(item: $chat.scannedText) { scan in
            ReadTextSheet(text: scan.text, presets: OCRLogic.scanPresetIDs.compactMap { app.presets.preset(id: $0) }) { preset, selection, text in
                chat.useScan(preset, selection: selection, text: text)
            }
        }
        // A preset with pickers (Reply to this) asks for its choices before it sends.
        .sheet(item: $chat.presetNeedingChoices) { preset in
            PresetOptionsSheet(preset: preset, message: chat.input) { selection, message in
                chat.finishChoices(preset, selection: selection, message: message)
            }
        }
    }

    /// "Read replies aloud": feeds the reply being written, and its end, to the speaker.
    private func followReply() {
        guard app.voice.settings.readRepliesAloud, let last = chat.messages.last, last.role == .assistant else { return }
        app.speaker.follow(messageID: last.id, text: last.content, isFinal: !chat.isStreaming, hub: app.voice)
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
            .hoverEffect(.highlight)
            .accessibilityHint("Shows a tip")
            .accessibilityIdentifier("home.greeting")
            HStack(spacing: 6) {
                if tip == nil, let model = chat.model { ModelLogo(brand: ModelBrand.resolve(model), size: greetingLogoSize) }
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
        .readableWidth()
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
                if let note = chat.offlineToolNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("offline-tool-note")
                }
            }
            // A container of its own, so the UI tests can measure the column.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.content")
            .padding(.vertical, 12)            .readableWidth()
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
