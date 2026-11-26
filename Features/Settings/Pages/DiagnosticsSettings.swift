import SwiftUI

/// Crash, hang and metric reports MetricKit delivered to this device, newest first, each shareable as JSON.
struct DiagnosticsSettings: View {
    @Environment(AppState.self) private var appState
    @State private var records: [DiagnosticRecord] = []
    @State private var memory: MemoryDiagnostics?
    @State private var stalls: [MainThreadStall] = []

    private func gigabytes(_ bytes: Int64) -> String { bytes > 0 ? FitFormat.gigabytes(bytes) : "Not reported" }

    private var entitlementText: String {
        switch memory?.entitlementSigned {
        case true?: "Signed in"
        case false?: "Not in this install"
        case nil: "Unknown"
        }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Budget for a model", value: gigabytes(memory?.budgetBytes ?? 0))
                LabeledContent("Memory limit", value: gigabytes(memory?.limitBytes ?? 0))
                LabeledContent("App memory in use", value: gigabytes(memory?.footprintBytes ?? 0))
                LabeledContent("Available to the app", value: gigabytes(memory?.availableBytes ?? 0))
                LabeledContent("Installed RAM", value: gigabytes(memory?.physicalBytes ?? 0))
                LabeledContent("Increased memory limit", value: entitlementText)
            } header: {
                Text("Memory")
            } footer: {
                Text("Read from this device just now. The budget is the limit minus 0.3 GB for the app itself; model fit checks use it.")
            }
            Section {
                if stalls.isEmpty {
                    Text("None since launch.")
                } else {
                    ForEach(stalls, id: \.date) { stall in
                        LabeledContent(stall.context) { Text("\(Int(stall.duration * 1000)) ms") }
                    }
                }
            } header: {
                Text("Main-thread stalls")
            } footer: {
                Text("Times the screen did not respond for over a quarter of a second, with what the app was doing.")
            }
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
        .task {
            records = appState.diagnostics.list()
            stalls = MainThreadWatchdog.shared.recent
            memory = await appState.memory.diagnostics()
        }
        .refreshable {
            stalls = MainThreadWatchdog.shared.recent
            memory = await appState.memory.diagnostics()
        }
    }
}
