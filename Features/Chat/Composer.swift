import PhotosUI
import SwiftUI

/// Chat input: a round "+" menu and a rounded field with a send, stop or presets button inside.
struct Composer: View {
    @Bindable var model: ChatViewModel
    var hasModel: Bool
    var presets: PresetStore?
    @State private var showsPresets = false
    @State private var showsPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var showsFiles = false
    /// Owned by the chat screen so a tap outside the card can dismiss the keyboard.
    var focused: FocusState<Bool>.Binding
    @Environment(AppSettings.self) private var settings
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(spacing: 8) {
            if let error = model.errorMessage {
                ErrorBanner(text: error) { model.dismissError() }
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
                // A floating control over the list, so it takes glass directly (with the model pill, the only such place).
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: ARTheme.radiusXL))
                .contentShape(.rect(cornerRadius: ARTheme.radiusXL))
                // A tap anywhere on the field focuses it; the field is not a Button, so there is no stock control for this.
                .onTapGesture { focused.wrappedValue = true }
            }
        }
        .frame(maxWidth: ARTheme.contentMaxWidth)
        .padding(.horizontal, ARTheme.pagePadding)
        .padding(.bottom, 8)
        // Send, stop and the buttons beside the field keep the keyboard up.
        .keepsKeyboardOnTap()
        .onChange(of: model.focusTick) { focused.wrappedValue = true }
        // A light tap when a send starts a reply (not on every reply end).
        .sensoryFeedback(.impact(weight: .light), trigger: model.isStreaming) { _, streaming in streaming }
        .photosPicker(isPresented: $showsPhotos, selection: $photoItems,
                      maxSelectionCount: AttachmentLogic.maxPerMessage, matching: .images)
        .onChange(of: photoItems) { _, items in loadPhotos(items) }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { model.attachImages([(data: $0, filename: "Photo.jpg")]) }.ignoresSafeArea()
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
            model.attachImages(images)
        }
    }

    /// Round button outside the field: photos, camera and files, then the Tools and thinking switches.
    private var plusMenu: some View {
        Menu {
            Section {
                Button("Photos", systemImage: "photo") { showsPhotos = true }
                    .accessibilityIdentifier("composer.add-photos")
                Button("Camera", systemImage: "camera") { showsCamera = true }
                    .disabled(!CameraPicker.isAvailable)
                    .accessibilityIdentifier("composer.add-camera")
                Button("Files", systemImage: "folder") { showsFiles = true }
                    .accessibilityIdentifier("composer.add-files")
            }
            if model.supportsTools {
                Section {
                    Toggle("Tools", systemImage: "puzzlepiece.extension", isOn: Binding(
                        get: { model.toolsEnabled },
                        set: { model.setToolsEnabled($0) }
                    ))
                    .accessibilityIdentifier("composer.tools-toggle")
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
        } label: {
            Label("Add", systemImage: "plus").labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel("Add")
    }

    @ViewBuilder
    private var trailingButton: some View {
        if model.isStreaming || !model.input.isEmpty || !model.pending.isEmpty {
            actionButton
        } else if presets != nil {
            Button { showsPresets = true } label: {
                Label("Presets", systemImage: "sparkles").labelStyle(.iconOnly).imageScale(.large)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            // The HIG minimum hit area; a borderless button is only as big as its symbol.
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Presets")
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if model.isStreaming {
            Button { model.stop() } label: {
                Label("Stop", systemImage: "stop.fill").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel("Stop")
        } else {
            Button { model.send() } label: {
                Label("Send", systemImage: "arrow.up").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(!model.canSend)
            .accessibilityLabel("Send")
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
