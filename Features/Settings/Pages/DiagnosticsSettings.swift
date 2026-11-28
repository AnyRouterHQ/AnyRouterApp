import SwiftUI

/// Crash, hang and metric reports MetricKit delivered to this device, newest first, each shareable as JSON.
struct DiagnosticsSettings: View {
    @Environment(AppState.self) private var appState
    @State private var records: [DiagnosticRecord] = []
    @State private var memory: MemoryDiagnostics?
    @State private var stalls: [MainThreadStall] = []
    @State private var exits: [AppExitCount] = []

    private func gigabytes(_ bytes: Int64) -> String { bytes > 0 ? FitFormat.gigabytes(bytes) : "Not reported" }

    private func signedText(_ signed: Bool?) -> String {
        switch signed {
        case true?: "Signed in"
        case false?: "Not in this install"
        case nil: "Unknown"
        }
    }

    private func reload() async {
        stalls = MainThreadWatchdog.shared.recent
        exits = appState.diagnostics.lastExitCounts()
        memory = await appState.memory.diagnostics()
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Budget for a model", value: gigabytes(memory?.budgetBytes ?? 0))
                LabeledContent("Memory limit", value: gigabytes(memory?.limitBytes ?? 0))
                LabeledContent("App memory in use", value: gigabytes(memory?.footprintBytes ?? 0))
                LabeledContent("Available to the app", value: gigabytes(memory?.availableBytes ?? 0))
                LabeledContent("Installed RAM", value: gigabytes(memory?.physicalBytes ?? 0))
                LabeledContent("Increased memory limit", value: signedText(memory?.entitlementSigned))
                LabeledContent("Extended address space", value: signedText(memory?.extendedAddressingSigned))
                LabeledContent("Largest file it can open", value: memory?.mappableBytes.map(FitFormat.gigabytes) ?? "Not measured")
            } header: {
                Text("Memory")
            } footer: {
                Text("Read from this device just now. The budget is the limit minus 0.3 GB for the app itself; model fit checks use it. A model file must fit the largest file it can open.")
            }
            if let checks = memory?.modelChecks, !checks.isEmpty {
                Section {
                    ForEach(checks, id: \.name) { check in
                        LabeledContent(check.name) { Text(check.verdict) }
                    }
                } header: {
                    Text("Fit check for local models")
                } footer: {
                    Text("A guess that blocks nothing: every model stays available. Where it doubts one, the line names the rule (address-space probe, streaming class or budget) and its numbers.")
                }
            }
            Section {
                if exits.isEmpty {
                    Text("None reported yet. iOS reports these about a day later.")
                } else {
                    ForEach(exits, id: \.self) { exit in
                        LabeledContent("\(exit.reason) (\(exit.phase.lowercased()))") { Text("\(exit.count)") }
                    }
                }
            } header: {
                Text("Times iOS ended the app")
            } footer: {
                Text("From the newest metrics report. Memory resource limit means the app used more memory than iOS allows.")
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
                                if let message = appState.diagnostics.modelListMessage(of: record)
                                    ?? appState.diagnostics.modelLoadTrace(of: record)?.summary {
                                    Text(message).font(.caption).foregroundStyle(.secondary)
                                }
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
            await reload()
        }
        .refreshable {
            await reload()
        }
    }
}
