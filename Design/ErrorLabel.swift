import SwiftUI

/// An error line: a red symbol with primary text. System red text on a white background is under 4.5:1.
struct ErrorLabel: View {
    let text: String
    let systemImage: String

    init(_ text: String, systemImage: String = "exclamationmark.triangle") {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.red)
        }
    }
}
