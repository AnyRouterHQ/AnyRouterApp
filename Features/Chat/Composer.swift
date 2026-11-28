import PhotosUI
import SwiftUI
import UIKit

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
    /// "Answer offline" found nothing installed: the smallest model that fits, waiting for a yes.
    @State private var offerDownload: LocalModelEntry?
    /// The speech model the voice button offered, while its download cover is up.
    @State private var voiceGate: VoiceModel?
    /// The cover closed because the model is in: listen as soon as it is gone.
    @State private var listensAfterGate = false
    /// What "Answer offline" did, said under the field until the next edit.
    @State private var deviceNote: String?
    /// Counts the person's Stop taps, for a firmer tap than the send one.
    @State private var stopCount = 0
    /// Owned by the chat screen so a tap outside the card can dismiss the keyboard.
    var focused: FocusState<Bool>.Binding
    @Environment(AppSettings.self) private var settings
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models
    @Environment(ShellModel.self) private var shell
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Half the one-line field height (48 pt), so one line is a capsule.
    @ScaledMetric(relativeTo: .body) private var fieldRadius: CGFloat = 24
    /// The round button keeps its 44 pt minimum at the default size and grows with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 44
    /// Between the field's edge and the 44 pt hit area of its button. The 36 pt circle in that area then sits 6 pt
    /// inside the 48 pt field, concentric with its ends.
    private let fieldInset: CGFloat = 2
    /// The + circle is as tall as the one-line field (48 pt), so the two read as one row.
    private var plusSize: CGFloat { buttonSize + 2 * fieldInset }

    // Outside `body`: inline, this binding put the modifier chain past the type checker's time limit (CI 46059650902).
    private var offerDownloadTitle: String { offerDownload.map(OfflineLogic.downloadQuestion) ?? "" }
    private var offerDownloadShown: Binding<Bool> {
        Binding(get: { offerDownload != nil }, set: { if !$0 { offerDownload = nil } })
    }

    /// The field and what sits around it. Split from `body` so the type checker keeps up with the long modifier chain.
    private var fieldStack: some View {
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
            QueuedMessagesView(model: model)
            if let error = app.dictation.errorMessage {
                ErrorBanner(text: error) { app.dictation.dismissError() }
            }
            if let notice = app.speaker.notice {
                ErrorBanner(text: notice) { app.speaker.dismissNotice() }
            }
            if app.dictation.isActive {
                DictationBar(dictation: app.dictation, hub: app.voice)
            }
            if let notice = deviceNote ?? model.modelNotice {
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
            if let presets, let suggestions {
                ComposerSuggestionsRow(
                    suggestions: suggestions, presets: presets,
                    onClipboard: { pasteClipboard($0) },
                    onPreset: { pick($0, mode: suggestions.mode) },
                    onSend: { model.sendNow($0) },
                    onEditPresets: { shell.presentSettings(closeSidebar: false, destination: .presets) },
                    onDismiss: { model.dismissPasteOffer(); app.clipboard.dismiss() })
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
            if !model.mentions.isEmpty {
                MentionChips(mentions: model.mentions) { model.removeMention($0) }
            }
            HStack(alignment: .bottom, spacing: 8) {
                // As tall as a one-line field and bottom aligned, so the + stays centred on its last line.
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
                            guard !press.modifiers.contains(.shift) else { return .ignored }
                            if model.canSend { _ = model.send() } else if model.canQueue { model.enqueue() }
                            return .handled
                        }
                        // As tall as the button on one line, so the placeholder sits in the middle of the field.
                        .padding(.vertical, 11)
                        .frame(minHeight: buttonSize)
                    trailingButton
                }
                .padding(.leading, 16)
                .padding(.trailing, fieldInset)
                .padding(.vertical, fieldInset)
                // A floating control over the list, so it takes glass directly (the only such place).
                // One line is a capsule; more lines keep the same corner radius.
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: fieldRadius))
                .contentShape(.rect(cornerRadius: fieldRadius))
                // A tap anywhere on the field focuses it; the field is not a Button, so there is no stock control for this.
                .onTapGesture { focused.wrappedValue = true }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: suggestions)
        .readableWidth()
        .padding(.bottom, 8)
        // Send, stop and the buttons beside the field keep the keyboard up.
        .keepsKeyboardOnTap()
        .onChange(of: model.focusTick) { focused.wrappedValue = true }
        .onChange(of: model.voiceTick) { app.dictation.begin(text: $model.input, hub: app.voice) }
        .onChange(of: model.input) { old, new in
            model.inputChanged(from: old, to: new)
            if new != old { deviceNote = nil }
            if !new.isEmpty { app.clipboard.dismiss() }
            if showsPluginList, new != old { showsPluginList = false }
            // New input cuts off the voice that is reading a reply.
            if new != old { app.speaker.stop() }
        }
        // Dictation ends with the screen: leaving the chat, or the app going to the background, keeps the words so far.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { app.dictation.finish() } else { app.clipboard.check(composerEmpty: model.input.isEmpty) }
        }
        .onDisappear { app.dictation.cancel() }
        .sheet(isPresented: Bindable(app.dictation).showsExplanation, onDismiss: {
            if app.dictation.phase == .idle { app.dictation.declineExplanation() }
        }) {
            VoicePermissionSheet(onContinue: { app.dictation.confirmExplanation() }, onNotNow: { app.dictation.declineExplanation() })
        }
        .modifier(ComposerHaptics(isStreaming: model.isStreaming, stopCount: stopCount,
                                  modelChoiceCount: model.modelChoiceCount, errorMessage: model.errorMessage))
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
        // Dictation starts after the cover is gone, so its first-use permission sheet is not dropped.
        .fullScreenCover(item: $voiceGate, onDismiss: {
            guard listensAfterGate else { return }
            listensAfterGate = false
            app.dictation.begin(text: $model.input, hub: app.voice)
        }) { offer in
            VoiceModeGate(
                model: offer, downloader: app.voice.downloader,
                onReady: {
                    app.voice.select(offer)
                    listensAfterGate = true
                    voiceGate = nil
                },
                onNotNow: {
                    app.voice.settings.voiceModeDeclined = true
                    voiceGate = nil
                })
        }
    }

    var body: some View {
        fieldStack
        .fileImporter(isPresented: $showsFiles, allowedContentTypes: AttachmentLogic.importableTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.attachFiles(urls) }
        }
        .confirmationDialog(
            offerDownloadTitle, isPresented: offerDownloadShown, titleVisibility: .visible, presenting: offerDownload
        ) { entry in
            Button("Download") {
                app.hub.download(entry)
                deviceNote = OfflineLogic.downloadingMessage(entry)
            }
        } message: { entry in
            Text(OfflineLogic.downloadMessage(entry))
        }
        .sheet(isPresented: $showsPresets) {
            if let presets {
                PresetSheet(store: presets, onPick: { pick($0, mode: .starters) }, onSend: { model.sendNow($0) })
            }
        }
        .task { app.clipboard.check(composerEmpty: model.input.isEmpty) }
        .task {
            guard settings.showKeyboardOnLaunch, !shell.didFocusComposerOnLaunch else { return }
            shell.didFocusComposerOnLaunch = true
            focused.wrappedValue = true
        }
    }

    /// A preset was chosen in the row, the More menu or the presets sheet. A phone use case runs its action; any other
    /// preset fills the composer the way its mode says.
    private func pick(_ preset: PromptPreset, mode: ComposerSuggestionMode) {
        if mode == .clipboard, let kind = app.clipboard.offeredKind {
            quickSend(preset, kind: kind)
            return
        }
        defer { app.clipboard.dismiss() }
        // Reading the clipboard here is the person's own tap. The row itself never reads the text.
        let clipboard = { UIPasteboard.general.string ?? "" }
        guard let action = preset.action else {
            model.choose(preset, mode: mode, clipboardText: clipboard)
            return
        }
        switch action {
        case .readPhoto:
            readsText = true
            showsPhotos = true
        case .goOffline:
            goOffline()
        case .askClipboard, .summarizeLink:
            model.run(action, clipboardText: clipboard)
        }
    }

    /// The copy's own chip: text or a link goes into the field to edit, an image under it. Reading the clipboard here
    /// is the person's tap; if they refuse the system's paste question, nothing happens and the offer stays.
    private func pasteClipboard(_ kind: ClipboardKind) {
        switch kind {
        case .text, .link:
            guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
            model.input = text
        case .image:
            guard let data = UIPasteboard.general.image?.pngData() else { return }
            model.attachImages([(data: data, filename: "Clipboard.png")])
        }
        app.clipboard.dismiss()
    }

    /// A quick action on the copy: read it in this tap and send at once. A refused read keeps the offer.
    private func quickSend(_ preset: PromptPreset, kind: ClipboardKind) {
        switch kind {
        case .text, .link:
            guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
            app.clipboard.dismiss()
            model.quickSend(preset, text: text, deviceLanguage: Locale.current.language.languageCode?.identifier ?? "en")
        case .image:
            guard let data = UIPasteboard.general.image?.pngData() else { return }
            app.clipboard.dismiss()
            if preset.action == .readPhoto { model.readText(from: [data]) } else { model.quickSend(preset, image: data) }
        }
    }

    private func goOffline() {
        switch OfflineLogic.plan(models: models.models, catalog: app.hub.catalog) {
        case .use(let device):
            model.choose(device)
            deviceNote = OfflineLogic.usingMessage(device)
        case .download(let entry):
            offerDownload = entry
        case .unavailable:
            deviceNote = OfflineLogic.nothingFitsMessage
        }
    }

    /// The chips above the field, or nil. Decided by `ComposerSuggestionLogic`.
    private var suggestions: ComposerSuggestions? {
        guard let presets else { return nil }
        return model.suggestions(presets: presets, clipboardKind: app.clipboard.offeredKind, isDictating: app.dictation.isActive,
                                 mentionPanelOpen: mentionQuery != nil || showsPluginList)
    }

    /// The words after an @ the user is typing, when the list has something to offer this model.
    private var mentionQuery: String? {
        mentionRows.isEmpty ? nil : ComposerMention.query(in: model.input)
    }

    /// Every plugin with its switch and the files of this chat, and the presets with pickers, minus what is already
    /// chosen. A model without tools sees the plugins and files disabled, with the reason.
    private var mentionRows: [MentionItem] {
        let modelSource = model.model?.source
        let chosen = Set(model.mentions.map(\.id))
        return ComposerMention.items(
            sources: app.tools.menuSources, files: model.mentionableFiles, presets: presets?.all ?? [],
            isOn: { app.tools.isOn($0, modelSource: modelSource) },
            unavailableReason: model.supportsTools ? nil : ComposerMention.noToolsReason)
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

    /// Opens Extract on the newest photo or PDF waiting in the composer, or empty when there is none.
    private func openExtract() {
        let file = model.pending.last { $0.kind == .image || $0.kind == .pdf }
        let seed = file.flatMap { file in
            model.attachmentStore.data(for: file).map { ExtractSeed(data: $0, filename: file.filename, isPDF: file.kind == .pdf) }
        }
        shell.presentExtract(seed: seed)
    }

    /// Round button outside the field: camera, photos and files, Read text, presets, plugins, the thinking switch, the Tools
    /// submenu and the memory readout, in that order from the top.
    private var plusMenu: some View {
        Menu {
            Section {
                Button("Camera", systemImage: "camera") { readsText = false; showsCamera = true }
                    .disabled(!CameraPicker.isAvailable)
                    .accessibilityIdentifier("composer.add-camera")
                Button("Photos", systemImage: "photo") { readsText = false; showsPhotos = true }
                    .accessibilityIdentifier("composer.add-photos")
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
                Button("Extract fields", systemImage: "doc.text.magnifyingglass") { openExtract() }
                    .accessibilityIdentifier("composer.extract")
                // The composer text becomes the state of a custom decision.
                Button("Decide about this", systemImage: "checklist") { shell.decide(about: model.input) }
                    .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("composer.decide")
            }
            Section {
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
                }
            }
            Section {
                if model.supportsThinking {
                    // Automatic: the root's switch style would split this menu row into blank rows.
                    Toggle("Enable thinking", systemImage: "brain", isOn: Binding(
                        get: { model.thinkingEnabled },
                        set: { model.setThinkingEnabled($0) }
                    ))
                    .toggleStyle(.automatic)
                }
                if model.supportsTools { ComposerToolsMenu(model: model) }
            }
            MemoryMenu()
        } label: {
            // A floating control beside the field, so it takes glass like the field: one 48 pt circle, the field's height.
            // Title 2 semibold draws the + about as tall and as heavy as the voice button's glyph; title 3 medium read
            // small and thin next to it (screenshots 46107915397).
            Label("Add", systemImage: "plus")
                .labelStyle(.iconOnly)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: plusSize, height: plusSize)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        // The menu lists from the top as written, even though it opens upward from the bottom of the screen.
        .menuOrder(.fixed)
        .accessibilityLabel("Add")
    }

    /// The round button at the end of the field. A circle of about 36 pt in a 44 pt hit area, the system's prominent glass: voice while empty, send with
    /// text or an attachment, stop while a reply streams.
    private var trailingButton: some View {
        let action = ComposerAction.current(isStreaming: model.isStreaming, hasInput: !model.input.isEmpty,
                                            hasAttachments: !model.pending.isEmpty, isDictating: app.dictation.isActive)
        return HStack(spacing: 0) {
            if action == .queue { actionButton(.stop, id: "composer.stop") }
            actionButton(action, id: "composer.action")
        }
    }

    private func actionButton(_ action: ComposerAction, id: String) -> some View {
        Button { perform(action) } label: {
            Label { Text(action.title) } icon: {
                Image(systemName: action.symbol)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, isActive: action == .stopDictation)
            }
            .labelStyle(.iconOnly)
            .font(.callout.weight(.semibold))
            .prominentLabel()
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .frame(minWidth: buttonSize, minHeight: buttonSize)
        .contentShape(.circle)
        .disabled((action == .send && !model.canSend) || (action == .queue && !model.canQueue))
        .accessibilityLabel(action.title)
        .accessibilityIdentifier(id)
    }

    private func perform(_ action: ComposerAction) {
        switch action {
        case .stop:
            stopCount += 1
            model.stop()
        case .send: _ = model.send()
        case .queue: model.enqueue()
        case .voice, .stopDictation:
            app.speaker.stop()
            if action == .voice, let offer = app.voice.voiceModeOffer() {
                voiceGate = offer
                return
            }
            app.dictation.toggle(text: $model.input, hub: app.voice)
        }
    }
}

/// The composer's taps as one modifier, so the field stack's chain stays short enough to type-check (CI 46064358407).
private struct ComposerHaptics: ViewModifier {
    let isStreaming: Bool
    let stopCount: Int
    let modelChoiceCount: Int
    let errorMessage: String?

    func body(content: Content) -> some View {
        content
            // A light tap when a send starts a reply (not on every reply end).
            .sensoryFeedback(.impact(weight: .light), trigger: isStreaming) { _, streaming in streaming }
            .sensoryFeedback(.impact(weight: .medium), trigger: stopCount)
            .sensoryFeedback(.selection, trigger: modelChoiceCount)
            // An error appearing, not each change of its text.
            .sensoryFeedback(.error, trigger: errorMessage) { old, new in old == nil && new != nil }
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
