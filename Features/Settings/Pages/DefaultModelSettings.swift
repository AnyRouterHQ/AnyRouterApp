import SwiftUI

/// Pick the model new chats start with.
struct DefaultModelSettings: View {
    @Environment(ModelStore.self) private var models

    private var sections: [PickerSection] { ModelPickerLogic.sections(models: models.models, query: "") }

    var body: some View {
        List {
            ForEach(sections, id: \.kind) { section in
                Section(section.title) {
                    ForEach(section.models) { model in
                        Button {
                            models.select(model)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    ModelLabel(model: model, style: .row).foregroundStyle(.primary)
                                    Text(ModelPickerLogic.subtitle(for: model)).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if models.selected?.id == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(!model.isInstalled)
                    }
                }
            }
        }
        .overlay {
            if models.models.isEmpty { ContentUnavailableView("No models yet", systemImage: "cube") }
        }
    }
}
