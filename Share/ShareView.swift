import SwiftUI

/// "Ask AnyRouter" in the share sheet: what is being shared, what to do with it, and a Send button.
struct ShareView: View {
    let model: ShareModel
    var opensApp: (URL) -> Void
    var finish: () -> Void
    var cancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                switch model.stage {
                case .loading:
                    ProgressView()
                case .ready:
                    Section("Sharing") { preview }
                    if model.offersActions {
                        Section {
                            Picker("Then", selection: Bindable(model).action) {
                                ForEach(ShareAction.allCases) { Text($0.title).tag($0) }
                            }
                        }
                    }
                case .saved:
                    Label("Opening AnyRouter. If it does not open, open it yourself: your share is waiting.", systemImage: "checkmark.circle")
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("Ask AnyRouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel, action: cancel) }
                if model.stage == .ready {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) { model.send(opensApp: opensApp) }
                            .accessibilityLabel("Send")
                    }
                }
            }
            .task(id: model.stage) {
                guard model.stage == .saved else { return }
                try? await Task.sleep(for: .seconds(1.2))
                finish()
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let text = model.joinedText {
            Text(text).lineLimit(6)
        }
        ForEach(model.files.indices, id: \.self) { index in
            Label(model.files[index].file.filename, systemImage: model.files[index].file.kind == .pdf ? "doc.richtext" : "photo")
        }
    }
}
