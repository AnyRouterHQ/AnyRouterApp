import SwiftUI

/// Top card of Settings: signed-in profile and spend, or the sign-in prompt.
struct AccountCard: View {
    @Environment(AppState.self) private var app
    @Environment(ModelStore.self) private var models
    @State private var signInError: String?

    private static let manageURL = URL(string: "https://anyrouter.dev/dashboard")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch app.account.state {
            case .signedOut: signedOut
            case .signingIn:
                HStack(spacing: 10) { ProgressView(); Text("Signing in…").foregroundStyle(.secondary) }
            case .signedIn: signedIn
            }
        }
        .padding(.vertical, 6)
        .task(id: app.account.state) { await app.account.refreshSummary() }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ARLogoMark(size: 36).foregroundStyle(ARColor.foreground)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AnyRouter").font(.headline)
                    Text("Sign in to use cloud models.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Button("Sign in with AnyRouter") { signIn() }.buttonStyle(.arFilled)
            if let signInError { Text(signInError).font(.footnote).foregroundStyle(ARColor.destructive) }
        }
    }

    private var signedIn: some View {
        let summary = app.account.summary
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Avatar(url: summary?.avatarURL, initials: summary?.initials ?? "A")
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary?.title ?? "AnyRouter account").font(.headline).lineLimit(1)
                    if let email = summary?.email, email != summary?.title {
                        Text(email).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let plan = summary?.plan {
                        Text("\(plan) plan").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                ARLogoMark(size: 22).foregroundStyle(ARColor.mutedForeground)
            }
            if let line = summary?.usageLine { Text(line).font(.subheadline) }
            HStack {
                Link("Manage on anyrouter.dev", destination: Self.manageURL).font(.subheadline)
                Spacer()
                Button("Sign out", role: .destructive) {
                    Task { await app.account.signOut(); await models.refresh() }
                }
                .font(.subheadline)
            }
        }
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

private struct Avatar: View {
    let url: URL?
    let initials: String

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Text(initials).font(.system(size: 18, weight: .semibold)).foregroundStyle(ARColor.accentForeground)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ARColor.accent)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
