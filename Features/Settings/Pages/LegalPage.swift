import SwiftUI

/// Short summary plus a link to the full text on anyrouter.dev.
struct LegalPage: View {
    enum Kind {
        case privacy, terms

        var url: URL {
            URL(string: self == .privacy ? "https://anyrouter.dev/privacy" : "https://anyrouter.dev/terms")!
        }

        var summary: String {
            switch self {
            case .privacy:
                "Chats stay on this device. Messages leave it only when you pick an AnyRouter cloud model, and then go to AnyRouter to be answered. The sign-in key is kept in the Keychain."
            case .terms:
                "The app is open source under the Apache License 2.0. Use of AnyRouter cloud models follows the AnyRouter terms of service."
            }
        }
    }

    let kind: Kind

    var body: some View {
        List {
            Section { Text(kind.summary) }
            Section { Link("Read the full text on anyrouter.dev", destination: kind.url) }
        }
    }
}
