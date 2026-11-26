import SwiftUI

/// Chat input: a rounded card with the text field and a send or stop button.
struct Composer: View {
    @Bindable var model: ChatViewModel
    var hasModel: Bool
    @FocusState private var focused: Bool

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
                    .focused($focused)
                    .submitLabel(.return)
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
                    Spacer()
                    actionButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .arCard(radius: ARTheme.radiusXL)
        }
        .frame(maxWidth: ARTheme.contentMaxWidth)
        .padding(.horizontal, ARTheme.pagePadding)
        .padding(.bottom, 8)
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
