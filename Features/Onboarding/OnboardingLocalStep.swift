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
        // The one primary action in the bottom bar; the scroll edge effect gives it depth, no painted band (review #7).
        .bottomActionBar(id: "onboarding.local.continue", isEnabled: localState == .installed, action: finish) {
            Text("Continue")
        } accessory: {
            EmptyView()
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
                Button("Cancel Download", role: .cancel) { hub.cancel(modelID: entry.id) }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.local.cancel")
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
