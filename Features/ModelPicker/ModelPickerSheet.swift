import SwiftUI

/// Basic model list. The grouped picker replaces this in the model picker PR.
struct ModelPickerSheet: View {
    @Environment(ModelStore.self) private var models
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(models.models) { model in
                Button {
                    models.select(model)
                    dismiss()
                } label: {
                    HStack {
                        Text(model.displayName).foregroundStyle(ARColor.foreground)
                        Spacer()
                        if models.selected?.id == model.id { Image(systemName: "checkmark") }
                    }
                }
                .disabled(!model.isInstalled)
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
