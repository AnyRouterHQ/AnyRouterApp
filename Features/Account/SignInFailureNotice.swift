import SwiftUI
import UIKit

/// A sign-in failure as one plain line, with the server's own text behind "Details" and a Copy button.
struct SignInFailureNotice: View {
    let raw: String
    var tint: Color = .red

    var body: some View {
        let plain = SignInFailureText.plain(for: raw)
        VStack(spacing: 4) {
            Text(plain).foregroundStyle(tint).multilineTextAlignment(.center)
            if raw != plain {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(raw).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("Copy") { UIPasteboard.general.string = raw }
                            .font(.caption)
                            .accessibilityIdentifier("signin-failure.copy")
                    }
                }
                .font(.caption)
            }
        }
        .font(.footnote)
        .accessibilityIdentifier("signin-failure")
    }
}
