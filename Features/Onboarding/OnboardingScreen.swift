import SwiftUI

/// First launch: pick how to chat. Apple Intelligence, a small local model, or AnyRouter cloud.
struct OnboardingScreen: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models

    var onFinish: () -> Void

    @State private var choice: OnboardingLogic.Choice?
    @State private var signInError: String?

    private var hub: any ModelHubService { app.hub }
    private var recommended: LocalModelEntry? { OnboardingLogic.recommendedLocal(in: hub.catalog) }
    private var appleAvailable: Bool { models.models.contains { $0.source == .apple && $0.isInstalled } }
    private var localState: DownloadState { recommended.map { hub.downloadState(for: $0.id) } ?? .notInstalled }
    private var signedIn: Bool { app.account.state.isSignedIn }

    private var canFinish: Bool {
        OnboardingLogic.canFinish(choice: choice, appleAvailable: appleAvailable, localState: localState, signedIn: signedIn)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        ARLogoMark(size: 52).foregroundStyle(.primary)
                        Text("Choose how to chat").font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text("You can change this any time in Settings.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)
                }
                Section {
                    option(.apple, title: "Apple Intelligence", detail: appleAvailable
                           ? "Private, on device. No download."
                           : "Not available on this device.", icon: "apple.logo", enabled: appleAvailable)
                    localOption
                    cloudOption
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            // The actions stay reachable at the bottom, above the home indicator.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button { finish() } label: { Text("Continue").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!canFinish)
                    Button("Skip for now") { onFinish() }
                        .controlSize(.large)
                }
                .padding()
                .background(.bar)
            }
        }
        .task { await hub.reload() }
    }

    // MARK: Options

    @ViewBuilder
    private var localOption: some View {
        option(.local, title: recommended?.descriptor.displayName ?? "Local model",
               detail: recommended?.summary ?? "Download a small model to run on this device.",
               icon: "iphone", enabled: recommended != nil,
               trailing: HubLogic.sizeText(recommended?.descriptor.sizeBytes))
        if choice == .local, let recommended {
            switch localState {
            case .notInstalled, .failed:
                Button("Download\(HubLogic.sizeText(recommended.descriptor.sizeBytes).map { " (\($0))" } ?? "")") {
                    hub.download(recommended)
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
    }

    @ViewBuilder
    private var cloudOption: some View {
        option(.cloud, title: "AnyRouter cloud", detail: "Hundreds of cloud models with one sign-in.", icon: "cloud", enabled: true)
        if choice == .cloud {
            switch app.account.state {
            case .signedOut:
                Button("Sign in with AnyRouter") { signIn() }
                if let signInError {
                    Text(signInError).font(.footnote).foregroundStyle(.secondary)
                    Button("Try again") { signIn() }
                }
            case .signingIn:
                HStack { ProgressView(); Text("Signing in…").foregroundStyle(.secondary) }
            case .signedIn:
                Label("Signed in", systemImage: "checkmark.circle.fill")
            }
        }
    }

    private func option(_ value: OnboardingLogic.Choice, title: String, detail: String, icon: String,
                        enabled: Bool, trailing: String? = nil) -> some View {
        let selected = choice == value
        return Button { choice = value } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).imageScale(.large).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title).font(.headline)
                        Spacer()
                        if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
        }
        .foregroundStyle(.primary)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Actions

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

    private func finish() {
        guard let choice else { return }
        Task {
            await models.refresh()
            if let id = OnboardingLogic.modelID(for: choice, models: models.models, local: recommended) {
                models.select(modelID: id)
            }
            onFinish()
        }
    }
}

#Preview("Onboarding") {
    let state = AppState()
    return OnboardingScreen {}
        .environment(state)
        .environment(state.models)
}
