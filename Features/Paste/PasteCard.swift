import SwiftUI

/// What the device itself found in a paste: pretty JSON, a decoded token, a cron summary, the frames of a trace, a color.
/// Shows nothing for plain text, which a decision model classifies instead.
struct PasteCard: View {
    let state: String

    var body: some View {
        let kind = PasteLogic.detect(state)
        let rows = PasteLogic.rows(kind)
        if !rows.isEmpty {
            Section(PasteLogic.title(kind)) {
                ForEach(rows, id: \.name) { row in
                    VStack(alignment: .leading) {
                        Text(row.name).font(.caption).foregroundStyle(.secondary)
                        Text(row.value).font(.body.monospaced()).textSelection(.enabled)
                    }
                }
            }
            .accessibilityIdentifier("paste-card")
        }
    }
}
