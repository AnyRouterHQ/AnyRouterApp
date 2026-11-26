import SwiftUI

/// Crash, hang and metric reports MetricKit delivered to this device, newest first, each shareable as JSON.
struct DiagnosticsSettings: View {
    @Environment(AppState.self) private var appState
    @State private var records: [DiagnosticRecord] = []

    var body: some View {
        List {
            if records.isEmpty {
                Section {
                    Text("No reports yet. iOS delivers crash, hang and metric reports about a day after they happen.")
                }
            } else {
                Section {
                    ForEach(records) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.kind.title)
                                Text(record.date, format: .dateTime.year().month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: record.url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                } footer: {
                    Text("The newest \(DiagnosticsStore.defaultLimit) are kept. A report can name functions and device details. It never holds your chats.")
                }
            }
        }
        .accessibilityIdentifier("diagnostics.list")
        .task { records = appState.diagnostics.list() }
    }
}
