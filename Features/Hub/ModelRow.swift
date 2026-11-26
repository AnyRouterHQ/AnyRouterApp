import SwiftUI

/// Status colors for fit and badges. System colors only.
enum ModelStatusColor {
    static func fit(_ entry: LocalModelEntry) -> Color {
        if entry.unavailableReason != nil { return .secondary }
        switch entry.fit {
        case .fits: return .green
        case .tight: return .orange
        case .wontFit: return .red
        case .unknown: return .secondary
        }
    }

    static func badge(_ tone: ModelBadge.Tone) -> Color {
        switch tone {
        case .neutral: .secondary
        case .info: .accentColor
        case .success: .green
        case .warning: .orange
        }
    }
}

/// One model in a Manage models list: name, a detail line, fit status, and progress while downloading.
struct ModelRow: View {
    let entry: LocalModelEntry
    let state: DownloadState
    var isDefault = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ModelLabel(model: entry.descriptor)
                if isDefault {
                    Spacer()
                    Image(systemName: "star.fill").foregroundStyle(.secondary).accessibilityLabel("Default model")
                }
            }
            Text(HubListOptions.detailLine(entry)).font(.subheadline).foregroundStyle(.secondary)
            statusLine
            if case .downloading(let progress) = state { progressView(progress, label: "Downloading") }
            if case .paused(let progress) = state { progressView(progress, label: "Paused") }
            if case .verifying = state { Text("Verifying").font(.caption).foregroundStyle(.secondary) }
            if case .failed(let message) = state { Text(message).font(.caption).foregroundStyle(.red) }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        let status = HubListOptions.fitStatus(entry, device: DeviceName.current)
        if status != nil || !entry.badges.isEmpty {
            HStack(spacing: 6) {
                if let status {
                    Text(status).foregroundStyle(ModelStatusColor.fit(entry))
                }
                ForEach(entry.badges, id: \.self) { badge in
                    Text(badge.label).foregroundStyle(ModelStatusColor.badge(badge.tone))
                }
            }
            .font(.caption)
        }
    }

    private func progressView(_ progress: Double?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let progress {
                ProgressView(value: min(max(progress, 0), 1)) {
                    Text("\(label) \(HubLogic.percent(progress))").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView { Text(label).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
