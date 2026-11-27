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
    @State private var showsInstructions = false

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
                VStack(spacing: 0) {
                    ModelTitle(name: chat?.model?.shortName, isLoading: models.isLoading) { shell.isModelPickerPresented = true }
                        // A popover under the title on iPad. On iPhone and in a compact iPad window the system turns it into the sheet.
                        .popover(isPresented: Bindable(shell).isModelPickerPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                            ModelPickerSheet(currentID: chat?.model?.id) { chat?.choose($0) }
                                .frame(minWidth: sizeClass == .regular ? 400 : nil, idealWidth: sizeClass == .regular ? 440 : nil,
                                       minHeight: sizeClass == .regular ? 520 : nil, idealHeight: sizeClass == .regular ? 640 : nil)
                        }
                    if let tag = InstructionsLogic.headerTag(chat: chat?.chatInstructions) {
                        Text(tag).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("chat.instructions-tag")
                    }
                }
            }
            // One group, so iOS 26 draws New chat and More in a single shared glass capsule.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { shell.newChat(closeSidebar: false) } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
                Menu {
                    Button("Instructions for this chat", systemImage: "text.badge.star") { showsInstructions = true }
                        .accessibilityIdentifier("chat.instructions")
                    Button("Compact conversation", systemImage: "rectangle.compress.vertical") { chat?.compactConversation() }
                        .disabled(!(chat?.canCompact ?? false))
                        .accessibilityIdentifier("chat.compact")
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
                .accessibilityIdentifier("chat.more")
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
        .toolApprovalDialog(app.toolApprovals) { callID in
            chat?.messages.last?.toolSteps.contains { $0.call.id == callID } ?? false
        }
        .sheet(isPresented: $showsInstructions) {
            ChatInstructionsSheet(current: chat?.chatInstructions, global: settings.systemPrompt) { chat?.setChatInstructions($0) }
        }
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
                                  skipsToolsOffline: { [app] in app.tools.skipsOffline($0) },
                                  webSearch: PreSearcher(
                                      isOn: { [app] in app.tools.canPreSearch(modelSource: $0) },
                                      search: { [app] query, context in
                                          await app.tools.preSearch(query: query, approver: app.toolApprovals, context: context)
                                      }))
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
    @Environment(ShellModel.self) private var shell
    @Bindable var chat: ChatViewModel
    let presets: PresetStore
    let subtitle: String
    let showsDetails: Bool
    @FocusState private var composerFocused: Bool
    /// A tapped-in tip that replaces the model subtitle until the chat changes.
    @State private var tip: String?
    /// The list follows the reply while true (see `ScrollFollow`).
    @State private var following = true
    /// The end marker of the list is on screen.
    @State private var atBottom = true
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
        .refreshesMemory(app.memory, activity: chat.memoryActivity)
        // A new reply cuts off the voice of the last one; "Read replies aloud" then follows the new reply as it arrives.
        .onChange(of: chat.isStreaming) { _, streaming in
            if streaming { app.speaker.stop() }
            shell.isReplyStreaming = streaming
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
        }
        .readableWidth()
        .sensoryFeedback(.selection, trigger: tip)
    }

    private var messageList: some View {
        let messages = chat.messages
        let lastID = messages.last?.id
        let switchNotes = SwitchNotes.make(messages)
        let compactions = Dictionary(chat.compactions.map { ($0.lastMessageID, $0) }, uniquingKeysWith: { first, _ in first })
        // ScrollViewReader, not a ScrollPosition binding: the binding is written on every scroll frame, which
        // re-evaluates the whole list (the perf baseline showed the scroll CPU more than doubling).
        return ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(messages) { message in
                    MessageRow(
                        message: message,
                        isStreamingThis: chat.isStreaming && message.id == lastID,
                        showsRegenerate: message.id == lastID && chat.canRegenerate,
                        onRegenerate: { chat.regenerate() },
                        switchNote: switchNotes[message.id],
                        showsDetails: showsDetails,
                        loadingModelName: message.id == lastID ? chat.loadingModelName : nil,
                        statusNote: message.id == lastID ? chat.statusNote : nil
                    )
                    if let compaction = compactions[message.id] { CompactionDivider(compaction: compaction) }
                }
                if let note = chat.compactionNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("compaction-note")
                }
                if let note = chat.offlineToolNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("offline-tool-note")
                }
                Color.clear.frame(height: 1).id("bottom")
                    .onScrollVisibilityChange { atBottom = $0 }
            }
            // A container of its own, so the UI tests can measure the column.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.content")
            .padding(.vertical, 12)            .readableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .defaultScrollAnchor(.bottom)
        .onScrollPhaseChange { old, new in
            following = ScrollFollow.following(from: old, to: new, atBottom: atBottom, was: following)
        }
        // A new message is the reader's own send or a regenerate: always show it.
        .onChange(of: messages.count) {
            following = true
            proxy.scrollTo("bottom", anchor: .bottom)
        }
        .onChange(of: messages.last?.toolTraceData) { if following { proxy.scrollTo("bottom", anchor: .bottom) } }
        .onChange(of: messages.last?.content.count) { if following { proxy.scrollTo("bottom", anchor: .bottom) } }
        .overlay(alignment: .bottom) {
            if ScrollFollow.showsJumpButton(following: following, atBottom: atBottom) {
                Button {
                    following = true
                    proxy.scrollTo("bottom", anchor: .bottom)
                } label: {
                    Label("Jump to latest", systemImage: "arrow.down").labelStyle(.iconOnly)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityIdentifier("jump-to-latest")
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ScrollFollow.showsJumpButton(following: following, atBottom: atBottom))
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
}
