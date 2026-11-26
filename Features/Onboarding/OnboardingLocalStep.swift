import SwiftUI

/// "Use on-device only" on a device without Apple Intelligence: download one small local model, then chat.
struct OnboardingLocalStep: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    var onFinish: () -> Void

    private var hub: any ModelHubService { app.hub }
    private var recommended: LocalModelEntry? { OnboardingLogic.recommendedLocal(in: hub.catalog) }
    private var localState: DownloadState { recommended.map { hub.downloadState(for: $0.id) } ?? .notInstalled }

    var body: some View {
        Form {
            Section {
                if let recommended {
                    VStack(alignment: .leading, spacing: 2) {
                        ModelLabel(model: recommended.descriptor)
                        Text(recommended.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    progress(for: recommended)
                } else {
                    Text("No on-device model fits this device. Go back to use AnyRouter cloud instead.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Run a model on this device")
            } footer: {
                Text("It runs without a connection. You can add more models later in Settings.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("On-device")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { finish() } label: { Text("Continue").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(localState != .installed)
                .frame(maxWidth: 560)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
        .task { await hub.reload() }
    }

    @ViewBuilder
    private func progress(for entry: LocalModelEntry) -> some View {
        switch localState {
        case .notInstalled, .failed:
            Button("Download\(HubLogic.sizeText(entry.descriptor.sizeBytes).map { " (\($0))" } ?? "")") {
                hub.download(entry)
            }
        case .downloading(let progress), .paused(let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloading")
                    Spacer()
                    Text(HubLogic.percent(progress)).foregroundStyle(.secondary)
                }
                if let progress { ProgressView(value: min(max(progress, 0), 1)) }
                else { ProgressView().progressViewStyle(.linear) }
                Text("Closing the app may pause the download.").font(.footnote).foregroundStyle(.secondary)
            }
        case .verifying:
            HStack { ProgressView(); Text("Verifying").foregroundStyle(.secondary) }
        case .installed:
            Label("Ready", systemImage: "checkmark.circle.fill")
        }
    }

    private func finish() {
        Task {
            await models.refresh()
            if let id = OnboardingLogic.modelID(for: .local, models: models.models, local: recommended) {
                models.select(modelID: id)
            }
            onFinish()
        }
    }
}
