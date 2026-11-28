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
    @State private var showsRename = false
    @State private var renameText = ""

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
                ModelTitle(
                    name: chat?.model?.shortName,
                    title: ChatHeaderLogic.title(
                        chat?.thread?.title, hasReply: chat?.thread?.messages.contains(where: { $0.role == .assistant }) ?? false),
                    tag: InstructionsLogic.headerTag(chat: chat?.chatInstructions),
                    isLoading: models.isLoading
                ) { shell.isModelPickerPresented = true }
                    // A popover under the title on iPad. On iPhone and in a compact iPad window the system turns it into the sheet.
                    .popover(isPresented: Bindable(shell).isModelPickerPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        // Regular width shows a popover, which closes with a tap outside; compact shows a sheet.
                        ModelPickerSheet(currentID: chat?.model?.id, showsClose: sizeClass != .regular) { chat?.choose($0) }
                            .frame(minWidth: sizeClass == .regular ? 400 : nil, idealWidth: sizeClass == .regular ? 440 : nil,
                                   minHeight: sizeClass == .regular ? 520 : nil, idealHeight: sizeClass == .regular ? 640 : nil)
                    }
            }
            // The title draws its own glass pill (ModelTitle); no shared toolbar glass on top of it.
            .sharedBackgroundVisibility(.hidden)
            // One group, so iOS 26 draws New chat and More in a single shared glass capsule.
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { shell.newChat(closeSidebar: false) } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        renameText = chat?.thread?.title ?? ""
                        showsRename = true
                    }
                    .disabled(chat?.thread == nil)
                    .accessibilityIdentifier("chat.rename")
                    Button("Instructions for this chat", systemImage: "text.badge.star") { showsInstructions = true }
                        .accessibilityIdentifier("chat.instructions")
                    if settings.useMemory, let chat {
                        Toggle(isOn: Binding(get: { chat.memoryOff }, set: { chat.setMemoryOff($0) })) {
                            Label("Don't use memory in this chat", systemImage: "brain")
                        }
                        .accessibilityIdentifier("chat.memoryOff")
                    }
                    if let fraction = chat?.contextFraction {
                        let meter = CompactionLogic.meter(fraction: fraction)
                        // Read-only: the meter sits beside the action that frees the room.
                        Button(meter.text, systemImage: meter.symbol) {}
                            .disabled(true)
                            .accessibilityIdentifier("chat.context")
                    }
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
        .animation(.easeInOut(duration: 0.3), value: chat?.messages.isEmpty)
        .task(id: shell.selectedThreadID) {
            prepare()
            applyInbound()
        }
        // On a window that already shows the fresh chat the task above does not run again.
        .onChange(of: shell.inbound?.id) { applyInbound() }
        // A chat restored at launch can open before the device models are listed; its waiting run goes on once they are.
        .onChange(of: models.models.map(\.id)) { chat?.resumeWaitingRun() }
        .toolApprovalDialog(app.toolApprovals) { callID in
            chat?.messages.last?.toolSteps.contains { $0.call.id == callID } ?? false
        }
        .alert("Rename chat", isPresented: $showsRename) {
            TextField("Title", text: $renameText)
                .accessibilityIdentifier("chat.rename.field")
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let thread = chat?.thread { ThreadActions.rename(thread, to: renameText) }
            }
            .accessibilityIdentifier("chat.rename.save")
        }
        .sheet(isPresented: $showsInstructions) {
            ChatInstructionsSheet(current: chat?.chatInstructions, global: settings.systemPrompt) { chat?.setChatInstructions($0) }
        }
    }

    /// Keeps the current model when it already shows the selected thread (a first send creates the thread itself).
    private func prepare() {
        if let chat, chat.thread?.id == shell.selectedThreadID { return }
        chat?.summarizeForMemory()
        chat?.stop()
        let thread = shell.selectedThreadID.flatMap(fetchThread)
        let model = ChatViewModel(thread: thread, context: context, registry: registry,
                                  settings: settings, models: models,
                                  toolHost: { [app] context in
                                      app.tools.makeHost(approver: context.approver ?? app.toolApprovals, context: DemoData.addingApprovalTool(to: context))
                                  },
                                  approver: app.toolApprovals,
                                  isOnline: { [app] in app.network.isOnline },
                                  skipsToolsOffline: { [app] in app.tools.skipsOffline($0) },
                                  webSearch: PreSearcher(
                                      isOn: { [app] in app.tools.canPreSearch(modelSource: $0) },
                                      search: { [app] query, context in
                                          await app.tools.preSearch(query: query, approver: app.toolApprovals, context: context)
                                      }))
        model.onThreadCreated = { [shell] id in shell.selectedThreadID = id }
        // "Read replies aloud" reads the end of a reply from here, also when a queued message starts the next one at once.
        model.onReplyEnded = { [app] id, text in
            guard app.voice.settings.readRepliesAloud else { return }
            app.speaker.follow(messageID: id, text: text, isFinal: true, hub: app.voice)
        }
        model.generatesTitles = true
        model.embedder = OnDeviceEmbedder.shared
        model.subagentsEnabled = { [app] in app.tools.isBuiltInEnabled(SubagentLogic.toolName) }
        model.extractor = AppleMemoryExtractor()
        Task { _ = await OnDeviceEmbedder.shared.prepare() }
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
    @Environment(\.scenePhase) private var scenePhase
    /// A tapped-in tip that replaces the model subtitle until the chat changes.
    @State private var tip: String?
    /// The notice before a question leaves the device for a cloud model ("Ask a cloud model").
    @State private var showsCloudNotice = false
    /// The list follows the reply while true (see `ScrollFollow`).
    @State private var following = true
    /// The end marker of the list is on screen.
    @State private var atBottom = true
    /// The list's height without the bars over it, and the height of the last question (see `ScrollFollow.settle`).
    @State private var visibleHeight: CGFloat = 0
    @State private var questionHeight: CGFloat = 0
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
        // Queued messages never go out while the app is in the background; they go when it is active again.
        .onChange(of: scenePhase) { _, phase in chat.setForeground(phase == .active) }
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
        .confirmationDialog(EscalationLogic.noticeTitle, isPresented: $showsCloudNotice, titleVisibility: .visible) {
            if let cloud = chat.escalationModel {
                Button(EscalationLogic.confirmTitle(for: cloud)) { chat.askCloudModel() }
                    .accessibilityIdentifier("reply.askCloud.confirm")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(EscalationLogic.noticeMessage)
        }
        // A preset with pickers (Reply to this) asks for its choices before it sends.
        .sheet(item: $chat.presetNeedingChoices) { preset in
            PresetOptionsSheet(preset: preset, message: chat.input) { selection, message in
                chat.finishChoices(preset, selection: selection, message: message)
            }
        }
    }

    /// "Read replies aloud": feeds the reply being written to the speaker. Its end comes from `onReplyEnded`.
    private func followReply() {
        guard chat.isStreaming, app.voice.settings.readRepliesAloud, let last = chat.messages.last, last.role == .assistant else { return }
        app.speaker.follow(messageID: last.id, text: last.content, isFinal: false, hub: app.voice)
    }

    /// With the keyboard up and the @ list open there is little room above the composer. The greeting then gives way
    /// (first the logo, then all of it) instead of pushing the composer under the keyboard.
    private var emptyState: some View {
        ViewThatFits(in: .vertical) {
            homeGreeting(showsLogo: true)
            homeGreeting(showsLogo: false)
            Color.clear
        }
        .readableWidth()
        .sensoryFeedback(.selection, trigger: tip)
    }

    private func homeGreeting(showsLogo: Bool) -> some View {
        VStack(spacing: 12) {
            Spacer()
            if showsLogo { ARLogoMark(size: 56) }
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
    }

    private func handle(_ action: ReplyFailure.Action) {
        switch action {
        case .retry: chat.regenerate()
        case .chooseModel: shell.isModelPickerPresented = true
        case .shortenChat: chat.compactConversation()
        case .askCloudModel: showsCloudNotice = true
        // The only reason to open Settings from a reply is a model on this device that did not load.
        case .openSettings: shell.presentSettings(closeSidebar: true, destination: .localModels)
        case .signIn:
            Task {
                do { try await app.account.signIn(mode: .signIn) } catch { chat.showError(error.localizedDescription) }
            }
        }
    }

    private func settle(_ proxy: ScrollViewProxy, _ event: ScrollFollow.Event, _ lastQuestionID: UUID?) {
        switch ScrollFollow.settle(after: event, lastQuestionID: lastQuestionID) {
        case .question(let id):
            following = false
            // A send puts the keyboard down, so the question and its reply get the whole view (manager, 2026-11-28). A send
            // adds the question and the empty reply together, so the event is a change of messages, not "last is a question".
            if case .messagesChanged = event { composerFocused = false }
            // The question's row is not laid out in the update that added it, so scrolling to it there found no target and
            // the view stayed where it was (verify-ui 46150715558, anchor PNGs). Scroll once that layout is done.
            Task { withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) } }
        case .bottom:
            following = true
            proxy.scrollTo("bottom", anchor: .bottom)
        case .stay:
            break
        }
    }

    private var messageList: some View {
        let messages = chat.messages
        let lastID = messages.last?.id
        let switchNotes = SwitchNotes.make(messages)
        let compactions = Dictionary(chat.compactions.map { ($0.lastMessageID, $0) }, uniquingKeysWith: { first, _ in first })
        let lastQuestionID = messages.last(where: { $0.role == .user })?.id
        let rowSpacing: CGFloat = 20
        let listPadding: CGFloat = 12
        let lastIsQuestion = messages.last?.role == .user
        // ScrollViewReader, not a ScrollPosition binding: the binding is written on every scroll frame, which
        // re-evaluates the whole list (the perf baseline showed the scroll CPU more than doubling).
        return ScrollViewReader { proxy in
        ScrollView {
            // A VStack, not a LazyVStack. The lazy stack placed rows it had not laid out at estimated heights: on a short
            // chat those estimates never settled, so after a swipe the list laid itself out without end (ShortChatTests),
            // and scrollTo("bottom") landed short of the end, the last row not even laid out (ScrollEndTests). Bisect runs
            // 46113949078 to 46129022686 cleared every other suspect, plain Text rows included.
            VStack(spacing: rowSpacing) {
                ForEach(messages) { message in
                    let row = MessageRow(
                        message: message,
                        // Live in any window: a second iPad window on this chat shows the reply as streaming, not as stopped.
                        isStreamingThis: LiveReplies.shared.ids.contains(message.id),
                        showsRegenerate: message.id == lastID && chat.canRegenerate,
                        onRegenerate: { chat.regenerate() },
                        switchNote: switchNotes[message.id],
                        showsDetails: showsDetails,
                        loadingModelName: message.id == lastID ? chat.loadingModelName : nil,
                        statusNote: message.id == lastID ? chat.statusNote : nil,
                        onFailureAction: handle,
                        canAskCloud: message.id == lastID && chat.escalationModel != nil
                    )
                    // The last turn is at least one view tall, so a new question can settle at the top (decision D27).
                    if message.id == lastID {
                        row.frame(
                            minHeight: ScrollFollow.lastRowMinHeight(
                                visible: visibleHeight, question: message.id == lastQuestionID ? nil : questionHeight,
                                spacing: rowSpacing, trailing: rowSpacing + 1 + listPadding),
                            alignment: .top)
                    } else if message.id == lastQuestionID {
                        row.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { questionHeight = $0 }
                    } else {
                        row
                    }
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
            .padding(.vertical, listPadding)            .readableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        // Hard at the bottom: under the floating composer a soft edge let reply text and trace rows read through the
        // field and beside the + button (HIG audit 2026-11-28 #4).
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        // While following, rows that finish their layout late (lazy rows, photos) keep the end on screen; after a send the
        // question stays put instead (screenshots 46014514092 opened the reply-parts thread above its end without this).
        .defaultScrollAnchor(following ? .bottom : nil, for: .sizeChanges)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        } action: { _, height in
            visibleHeight = height
        }
        // Rows that finish their layout late (photo and file cards, text views) grew the end of the chat after it opened,
        // so the "Reply parts" thread opened about 250 pt short of its end (lane B, screenshots 46075429647). While
        // following, any growth of the content keeps the end on screen.
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { old, new in
            if following, new > old { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .onScrollPhaseChange { old, new in
            following = ScrollFollow.following(from: old, to: new, atBottom: atBottom, was: following)
        }
        // A send or a regenerate puts the question at the top while the reply streams; anything else shows the end.
        .onChange(of: messages.count) {
            settle(proxy, .messagesChanged(isStreaming: chat.isStreaming, lastIsQuestion: lastIsQuestion), lastQuestionID)
        }
        .onChange(of: chat.isStreaming) { _, streaming in
            settle(proxy, streaming ? .streamStarted : .streamEnded, lastQuestionID)
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
