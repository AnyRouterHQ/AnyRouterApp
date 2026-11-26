import SwiftUI

/// Model picker: search, groups by source, install state, sign-in prompt.
struct ModelPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models
    @Environment(ShellModel.self) private var shell
    @Environment(\.dismiss) private var dismiss

    /// The model the chat uses now.
    var currentID: String?
    /// Called with the pick; the chat applies it to the next message.
    var onSelect: (ModelDescriptor) -> Void

    @State private var query = ""
    @State private var signInError: String?

    var body: some View {
        let sections = ModelPickerLogic.sections(models: models.models, query: query)
        return VStack(spacing: 0) {
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
                // Lazy: the cloud list has hundreds of rows.
                LazyVStack(spacing: 8) {
                    ForEach(sections) { section in
                        ARSectionTitle(section.title)
                            .padding(.top, 12)
                        if section.kind == .anyrouter { cloudPrompt(isEmpty: section.models.isEmpty) }
                        ForEach(section.models) { model in row(model) }
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

    private func fitDetail(for model: ModelDescriptor) -> FitDetail? {
        guard model.source == .gguf || model.source == .mlx else { return nil }
        return app.hub.catalog.first { $0.id == model.id }?.fitDetail
    }

    /// "GGUF · 2.5 GB", plus what the model needs in memory when the fit check has numbers for it.
    private func subtitle(for model: ModelDescriptor) -> String {
        let base = ModelPickerLogic.subtitle(for: model)
        guard let detail = fitDetail(for: model) else { return base }
        return "\(base) · \(FitText.needs(detail))"
    }

    private func row(_ model: ModelDescriptor) -> some View {
        let isSelected = currentID == model.id
        return Button {
            onSelect(model)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.shortName).font(.arBase).foregroundStyle(ARColor.foreground).lineLimit(1)
                    Text(subtitle(for: model)).font(.arXS).foregroundStyle(ARColor.mutedForeground)
                }
                Spacer()
                if let detail = fitDetail(for: model), let badge = FitText.badge(detail, device: DeviceName.current) {
                    ARChip(text: badge, tint: detail.verdict == .fits ? .green : detail.verdict == .tight ? .orange : ARColor.destructive)
                }
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
