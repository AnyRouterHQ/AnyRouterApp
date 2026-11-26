import PhotosUI
import SwiftUI

/// Chat input: a round "+" menu and a capsule field with one round button inside (voice, send or stop).
struct Composer: View {
    @Bindable var model: ChatViewModel
    var hasModel: Bool
    var presets: PresetStore?
    @State private var showsPresets = false
    @State private var showsPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var showsFiles = false
    /// The @ list was opened from the + menu instead of by typing an @.
    @State private var showsPluginList = false
    /// The photo or camera picker that is open reads text into the composer instead of attaching the image.
    @State private var readsText = false
    /// Owned by the chat screen so a tap outside the card can dismiss the keyboard.
    var focused: FocusState<Bool>.Binding
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var app
    @Environment(ShellModel.self) private var shell
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var fieldRadius: CGFloat = 26

    var body: some View {
        VStack(spacing: 8) {
            if let query = mentionQuery ?? (showsPluginList ? "" : nil) {
                let close: (() -> Void)? = mentionQuery == nil ? { showsPluginList = false } : nil
                MentionSuggestions(items: ComposerMention.filter(mentionRows, query: query), onClose: close) { item in
                    if case .preset(let id) = item.kind {
                        if let preset = presets?.preset(id: id) { model.choosePreset(preset) }
                    } else {
                        model.addMention(item)
                    }
                    showsPluginList = false
                }
            }
            if let error = model.errorMessage {
                ErrorBanner(text: error) { model.dismissError() }
            }
            if let error = app.dictation.errorMessage {
                ErrorBanner(text: error) { app.dictation.dismissError() }
            }
            if let notice = app.speaker.notice {
                ErrorBanner(text: notice) { app.speaker.dismissNotice() }
            }
            if app.dictation.isActive {
                DictationBar(dictation: app.dictation, hub: app.voice)
            }
            if let notice = model.modelNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            if !model.pending.isEmpty || model.ingesting > 0 {
                PendingAttachments(attachments: model.pending, ingesting: model.ingesting,
                                   failed: model.failedAttachmentIDs, store: model.attachmentStore) { model.removePending($0) }
            }
            if let note = model.attachmentNote {
                HStack(spacing: 8) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                    if model.visionAlternative != nil {
                        Button(AttachmentLogic.switchToVisionTitle) { model.switchToVisionModel() }
                            .font(.caption)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("composer.switch-to-vision")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            if model.pasteOffered, let presets, !presets.pasteOffered.isEmpty {
                PasteOfferRow(presets: presets.pasteOffered, onPick: { model.applyToPaste($0) }, onDismiss: { model.dismissPasteOffer() })
            }
            if !model.mentions.isEmpty {
                MentionChips(mentions: model.mentions) { model.removeMention($0) }
            }
            HStack(alignment: .bottom, spacing: 8) {
                plusMenu
                HStack(alignment: .bottom, spacing: 6) {
                    TextField("", text: $model.input, prompt: Text(hasModel ? "Ask anything" : "Choose a model to start"),
                              axis: .vertical)
                        .font(.body)
                        .lineLimit(1...6)
                        .focused(focused)
                        .accessibilityIdentifier("composer.input")
                        .submitLabel(.return)
                        // Hardware keyboards: Return sends, Shift-Return adds a line.
                        .onKeyPress(.return, phases: .down) { press in
                            guard !press.modifiers.contains(.shift), !model.isStreaming else { return .ignored }
                            if model.canSend { _ = model.send() }
                            return .handled
                        }
                        .padding(.vertical, 8)
                    trailingButton
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                // A floating control over the list, so it takes glass directly (the only such place).
                // One line is a capsule; more lines keep the same corner radius.
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: fieldRadius))
                .contentShape(.rect(cornerRadius: fieldRadius))
                // A tap anywhere on the field focuses it; the field is not a Button, so there is no stock control for this.
                .onTapGesture { focused.wrappedValue = true }
            }
        }
        .readableWidth()
        .padding(.bottom, 8)
        // Send, stop and the buttons beside the field keep the keyboard up.
        .keepsKeyboardOnTap()
        .onChange(of: model.focusTick) { focused.wrappedValue = true }
        .onChange(of: model.input) { old, new in
            model.inputChanged(from: old, to: new)
            if showsPluginList, new != old { showsPluginList = false }
            // New input cuts off the voice that is reading a reply.
            if new != old { app.speaker.stop() }
        }
        // Dictation ends with the screen: leaving the chat, or the app going to the background, keeps the words so far.
        .onChange(of: scenePhase) { _, phase in if phase != .active { app.dictation.finish() } }
        .onDisappear { app.dictation.cancel() }
        .sheet(isPresented: Bindable(app.dictation).showsExplanation, onDismiss: {
            if app.dictation.phase == .idle { app.dictation.declineExplanation() }
        }) {
            VoicePermissionSheet(onContinue: { app.dictation.confirmExplanation() }, onNotNow: { app.dictation.declineExplanation() })
        }
        // A light tap when a send starts a reply (not on every reply end).
        .sensoryFeedback(.impact(weight: .light), trigger: model.isStreaming) { _, streaming in streaming }
        .photosPicker(isPresented: $showsPhotos, selection: $photoItems,
                      maxSelectionCount: AttachmentLogic.maxPerMessage, matching: .images)
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker {
                if readsText { model.readText(from: [$0]) } else { model.attachImages([(data: $0, filename: "Photo.jpg")]) }
                readsText = false
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: AttachmentLogic.importableTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.attachFiles(urls) }
        }
        .sheet(isPresented: $showsPresets) {
            if let presets {
                PresetSheet(store: presets, onPick: { model.usePreset($0) }, onSend: { model.sendNow($0) })
            }
        }
        .task {
            guard settings.showKeyboardOnLaunch, !shell.didFocusComposerOnLaunch else { return }
            shell.didFocusComposerOnLaunch = true
            focused.wrappedValue = true
        }
    }

    /// The words after an @ the user is typing, when the list has something to offer this model.
    private var mentionQuery: String? {
        mentionRows.isEmpty ? nil : ComposerMention.query(in: model.input)
    }

    /// Plugins that are on and the files of this chat (when this model can use tools), and the presets with pickers,
    /// minus what is already chosen.
    private var mentionRows: [MentionItem] {
        let tools = model.supportsTools
        let modelSource = model.model?.source
        let sources = tools ? app.tools.menuSources.filter { app.tools.isOn($0, modelSource: modelSource) } : []
        let chosen = Set(model.mentions.map(\.id))
        return ComposerMention.items(sources: sources, files: tools ? model.mentionableFiles : [], presets: presets?.all ?? [])
            .filter { !chosen.contains($0.id) }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            var images: [(data: Data, filename: String)] = []
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    images.append((data: data, filename: "Photo \(index + 1).jpg"))
                }
            }
            if readsText { model.readText(from: images.map(\.data)) } else { model.attachImages(images) }
            readsText = false
        }
    }

    /// Round button outside the field: photos, camera and files, presets, the Tools and thinking switches, and the memory readout.
    private var plusMenu: some View {
        Menu {
            Section {
                Button("Photos", systemImage: "photo") { readsText = false; showsPhotos = true }
                    .accessibilityIdentifier("composer.add-photos")
                Button("Camera", systemImage: "camera") { readsText = false; showsCamera = true }
                    .disabled(!CameraPicker.isAvailable)
                    .accessibilityIdentifier("composer.add-camera")
                Button("Files", systemImage: "folder") { showsFiles = true }
                    .accessibilityIdentifier("composer.add-files")
                // Reads the text on the device, then offers Translate, Split this bill or Summarize.
                Menu("Read text", systemImage: "text.viewfinder") {
                    Button("Photos", systemImage: "photo") { readsText = true; showsPhotos = true }
                        .accessibilityIdentifier("composer.read-photos")
                    Button("Camera", systemImage: "camera") { readsText = true; showsCamera = true }
                        .disabled(!CameraPicker.isAvailable)
                        .accessibilityIdentifier("composer.read-camera")
                }
                .accessibilityIdentifier("composer.read-text")
            }
            if presets != nil {
                Button("Presets", systemImage: "sparkles") { showsPresets = true }
                    .accessibilityIdentifier("composer.presets")
            }
            if model.supportsTools {
                Button("Plugins", systemImage: "at") {
                    showsPluginList = true
                    focused.wrappedValue = true
                }
                .accessibilityIdentifier("composer.plugins")
                Section {
                    Toggle("Tools", systemImage: "puzzlepiece.extension", isOn: Binding(
                        get: { model.toolsEnabled },
                        set: { model.setToolsEnabled($0) }
                    ))
                    .accessibilityIdentifier("composer.tools-toggle")
                    if model.toolsEnabled {
                        // The same icons as Settings › Integrations.
                        ForEach(app.tools.menuSources) { source in
                            Toggle(isOn: Binding(
                                get: { app.tools.isOn(source, modelSource: model.model?.source) },
                                set: { app.tools.setSource(source, on: $0) }
                            )) {
                                Label {
                                    Text(OfflineLogic.sourceTitle(source.title, needsNetwork: source.id != ToolSourceCatalog.device.id,
                                                                  isOffline: app.network.isOffline))
                                } icon: { ToolSourceIcon(icon: source.icon) }
                            }
                            .accessibilityIdentifier("composer.tool-source.\(source.id)")
                        }
                    }
                }
            }
            if model.supportsThinking {
                Section {
                    Toggle("Enable thinking", systemImage: "brain", isOn: Binding(
                        get: { model.thinkingEnabled },
                        set: { model.setThinkingEnabled($0) }
                    ))
                }
            }
            MemoryMenu()
        } label: {
            Label("Add", systemImage: "plus").labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel("Add")
    }

    /// The round button at the end of the field. 44 pt, the system's prominent glass: voice while empty, send with
    /// text or an attachment, stop while a reply streams.
    private var trailingButton: some View {
        let action = ComposerAction.current(isStreaming: model.isStreaming, hasInput: !model.input.isEmpty,
                                            hasAttachments: !model.pending.isEmpty, isDictating: app.dictation.isActive)
        return Button { perform(action) } label: {
            Label { Text(action.title) } icon: {
                Image(systemName: action.symbol)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, isActive: action == .stopDictation)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .frame(minWidth: 44, minHeight: 44)
        .disabled(action == .send && !model.canSend)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier("composer.action")
    }

    private func perform(_ action: ComposerAction) {
        switch action {
        case .stop: model.stop()
        case .send: _ = model.send()
        case .voice, .stopDictation:
            app.speaker.stop()
            app.dictation.toggle(text: $model.input, hub: app.voice)
        }
    }
}

/// An error above the composer: a red label and the system close button.
struct ErrorBanner: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(role: .close, action: onDismiss)
        }
        .padding(12)
        .background(.red.opacity(0.12), in: .rect(cornerRadius: ARTheme.radius))
    }
}
