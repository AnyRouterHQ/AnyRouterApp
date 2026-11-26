import SwiftUI

/// First launch (Atomic `onboarding`): pick how to chat. Apple Intelligence, a small local model, or AnyRouter cloud.
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
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ARLogoMark(size: 52).foregroundStyle(ARColor.foreground).padding(.top, 48)
                    Text("Choose how to chat").font(.arHero).foregroundStyle(ARColor.foreground).padding(.top, 8)
                    Text("You can change this any time in Settings.")
                        .font(.arSM).foregroundStyle(ARColor.mutedForeground).padding(.bottom, 16)
                    option(.apple, title: "Apple Intelligence", detail: appleAvailable
                           ? "Private, on device. No download."
                           : "Not available on this device.", icon: "apple.logo", enabled: appleAvailable)
                    localOption
                    cloudOption
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, ARTheme.pagePadding)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 10) {
                Button("Continue") { finish() }
                    .buttonStyle(.arFilled)
                    .disabled(!canFinish)
                    .opacity(canFinish ? 1 : 0.4)
                Button("Skip for now") { onFinish() }
                    .font(.arSM)
                    .foregroundStyle(ARColor.mutedForeground)
            }
            .frame(maxWidth: 560)
            .padding(ARTheme.pagePadding)
        }
        .background(ARColor.background.ignoresSafeArea())
        .task { await hub.reload() }
    }

    // MARK: Options

    private var localOption: some View {
        VStack(spacing: 10) {
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
                    .buttonStyle(.arFilled)
                case .downloading(let progress), .paused(let progress):
                    VStack(spacing: 6) {
                        HStack {
                            Text("Downloading").font(.arSM).foregroundStyle(ARColor.foreground)
                            Spacer()
                            Text(HubLogic.percent(progress)).font(.arSM).foregroundStyle(ARColor.mutedForeground)
                        }
                        if let progress { ProgressView(value: min(max(progress, 0), 1)).tint(ARColor.accent) }
                        else { ProgressView().progressViewStyle(.linear).tint(ARColor.accent) }
                        Text("Closing the app may pause the download.")
                            .font(.arXS).foregroundStyle(ARColor.mutedForeground)
                    }
                case .verifying:
                    HStack { ProgressView(); Text("Verifying").font(.arSM).foregroundStyle(ARColor.mutedForeground) }
                case .installed:
                    Label("Ready", systemImage: "checkmark.circle.fill").font(.arSM).foregroundStyle(ARColor.accent)
                }
            }
        }
    }

    private var cloudOption: some View {
        VStack(spacing: 10) {
            option(.cloud, title: "AnyRouter cloud", detail: "Hundreds of cloud models with one sign-in.", icon: "cloud", enabled: true)
            if choice == .cloud {
                switch app.account.state {
                case .signedOut:
                    Button("Sign in with AnyRouter") { signIn() }.buttonStyle(.arFilled)
                    if let signInError { Text(signInError).font(.arXS).foregroundStyle(ARColor.destructive) }
                case .signingIn:
                    HStack { ProgressView(); Text("Signing in…").font(.arSM).foregroundStyle(ARColor.mutedForeground) }
                case .signedIn:
                    Label("Signed in", systemImage: "checkmark.circle.fill").font(.arSM).foregroundStyle(ARColor.accent)
                }
            }
        }
    }

    private func option(_ value: OnboardingLogic.Choice, title: String, detail: String, icon: String,
                        enabled: Bool, trailing: String? = nil) -> some View {
        let selected = choice == value
        return Button { choice = value } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).frame(width: 28).foregroundStyle(ARColor.foreground)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ARColor.foreground)
                        Spacer()
                        if let trailing { Text("· \(trailing)").font(.arSM).foregroundStyle(ARColor.mutedForeground) }
                    }
                    Text(detail).font(.arSM).foregroundStyle(ARColor.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? ARColor.accent : ARColor.mutedForeground)
            }
            .padding(14)
            .arCard(radius: ARTheme.radiusLarge)
            .overlay(RoundedRectangle(cornerRadius: ARTheme.radiusLarge, style: .continuous)
                .strokeBorder(selected ? ARColor.foreground : .clear, lineWidth: 1.5))
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
