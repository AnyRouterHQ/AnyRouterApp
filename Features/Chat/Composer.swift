import SwiftUI

/// Chat input: a rounded card with the text field and a send or stop button.
struct Composer: View {
    @Bindable var model: ChatViewModel
    var hasModel: Bool
    var presets: PresetStore?
    @State private var showsPresets = false
    /// Owned by the chat screen so a tap outside the card can dismiss the keyboard.
    var focused: FocusState<Bool>.Binding
    @Environment(AppSettings.self) private var settings
    @Environment(ShellModel.self) private var shell

    var body: some View {
        VStack(spacing: 8) {
            if let error = model.errorMessage {
                ErrorBanner(text: error) { model.dismissError() }
            }
            VStack(spacing: 6) {
                TextField("", text: $model.input, prompt: Text(hasModel ? "Ask anything" : "Choose a model to start")
                    .foregroundStyle(ARColor.mutedForeground), axis: .vertical)
                    .font(.arBase)
                    .foregroundStyle(ARColor.foreground)
                    .lineLimit(1...6)
                    .focused(focused)
                    .submitLabel(.return)
                    // Hardware keyboards: Return sends, Shift-Return adds a line.
                    .onKeyPress(.return, phases: .down) { press in
                        guard !press.modifiers.contains(.shift), !model.isStreaming else { return .ignored }
                        if model.canSend { _ = model.send() }
                        return .handled
                    }
                    .padding(.horizontal, 4)
                HStack {
                    Button {} label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(ARColor.mutedForeground)
                            .frame(width: 32, height: 32)
                    }
                    .disabled(true)
                    .accessibilityLabel("Attachments, coming soon")
                    if let presets, model.input.isEmpty, !model.isStreaming {
                        Button { showsPresets = true } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(ARColor.mutedForeground)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Presets")
                    }
                    Spacer()
                    actionButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .arGlass(in: RoundedRectangle(cornerRadius: ARTheme.radiusXL, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ARTheme.radiusXL, style: .continuous))
            .onTapGesture { focused.wrappedValue = true }
        }
        .frame(maxWidth: ARTheme.contentMaxWidth)
        .padding(.horizontal, ARTheme.pagePadding)
        .padding(.bottom, 8)
        .onChange(of: model.focusTick) { focused.wrappedValue = true }
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

    @ViewBuilder
    private var actionButton: some View {
        if model.isStreaming {
            Button { model.stop() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ARColor.primaryForeground)
                    .frame(width: 32, height: 32)
                    .background(ARColor.primary, in: Circle())
            }
            .accessibilityLabel("Stop")
        } else {
            Button { model.send() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ARColor.primaryForeground)
                    .frame(width: 32, height: 32)
                    .background(ARColor.primary.opacity(model.canSend ? 1 : 0.3), in: Circle())
            }
            .disabled(!model.canSend)
            .accessibilityLabel("Send")
        }
    }
}

struct ErrorBanner: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.arSM).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(ARColor.destructive)
        .padding(12)
        .background(ARColor.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
    }
}
