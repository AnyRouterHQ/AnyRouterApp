import SwiftUI

/// Model picker: search, groups by source, install state, sign-in prompt.
struct ModelPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models
    @Environment(ShellModel.self) private var shell
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var signInError: String?

    private var sections: [PickerSection] {
        ModelPickerLogic.sections(models: models.models, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose model").font(.arXL).foregroundStyle(ARColor.foreground)
                Spacer()
                Button("Done") { dismiss() }.font(.arBase)
            }
            .padding(.horizontal, ARTheme.pagePadding)
            .padding(.top, 20)
            ARSearchField(text: $query, prompt: "Search models")
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.vertical, 12)
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(sections) { section in
                        VStack(spacing: 8) {
                            ARSectionTitle(section.title)
                            if section.kind == .anyrouter { cloudPrompt(isEmpty: section.models.isEmpty) }
                            ForEach(section.models) { model in row(model) }
                        }
                    }
                    if sections.allSatisfy({ $0.models.isEmpty }) && !query.isEmpty {
                        Text("No matching models").font(.arSM).foregroundStyle(ARColor.mutedForeground)
                    }
                    browseRow
                }
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.bottom, 24)
            }
        }
        .background(ARColor.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ model: ModelDescriptor) -> some View {
        let isSelected = models.selected?.id == model.id
        return Button {
            models.select(model)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName).font(.arBase).foregroundStyle(ARColor.foreground).lineLimit(1)
                    Text(ModelPickerLogic.subtitle(for: model)).font(.arXS).foregroundStyle(ARColor.mutedForeground)
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(ARColor.accent) }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .arCard(radius: ARTheme.radius)
            .overlay(RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous)
                .strokeBorder(isSelected ? ARColor.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cloudPrompt(isEmpty: Bool) -> some View {
        switch app.account.state {
        case .signedOut where isEmpty:
            VStack(spacing: 8) {
                Text("Sign in to use cloud models through AnyRouter.")
                    .font(.arSM).foregroundStyle(ARColor.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Sign in with AnyRouter") { signIn() }.buttonStyle(.arFilled)
                if let signInError { Text(signInError).font(.arXS).foregroundStyle(ARColor.destructive) }
            }
            .padding(12)
            .arCard(radius: ARTheme.radius)
        case .signingIn:
            HStack { ProgressView(); Text("Signing in…").font(.arSM).foregroundStyle(ARColor.mutedForeground); Spacer() }
                .padding(12)
        case .signedIn where isEmpty:
            Text("No cloud models available.").font(.arSM).foregroundStyle(ARColor.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
        default:
            EmptyView()
        }
    }

    private var browseRow: some View {
        Button {
            dismiss()
            shell.open(.hub, closeSidebar: true)
        } label: {
            HStack {
                Image(systemName: "square.stack.3d.up")
                Text("Browse more models").font(.arBase)
                Spacer()
                Image(systemName: "chevron.right").font(.arXS)
            }
            .foregroundStyle(ARColor.foreground)
            .padding(12)
            .arCard(radius: ARTheme.radius)
        }
        .buttonStyle(.plain)
    }

    private func signIn() {
        signInError = nil
        Task {
            do {
                try await app.account.signIn()
                await models.refresh()
            } catch {
                signInError = error.localizedDescription
            }
        }
    }
}
