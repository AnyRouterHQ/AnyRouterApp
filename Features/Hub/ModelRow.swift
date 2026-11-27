import SwiftUI

/// Status colors for fit and badges. System colors only.
enum ModelStatusColor {
    static func fit(_ entry: LocalModelEntry) -> Color {
        if entry.unavailableReason != nil { return .secondary }
        switch entry.fit {
        // Colour only where it means something: a warning. "Runs well" is plain secondary text (it failed contrast in green).
        case .fits: return .secondary
        case .tight: return .orange
        case .wontFit: return .red
        case .unknown: return .secondary
        }
    }

    static func badge(_ tone: ModelBadge.Tone) -> Color {
        switch tone {
        case .neutral: .secondary
        case .info: ARPalette.tint
        case .success: .green
        case .warning: .orange
        }
    }
}

/// One model in a Local Models list, as a `ListRow`: logo and name; then the engine, size and memory line and a status
/// line (fit, badges, download progress, failure) in the two secondary lines; Default and a download ring at the end.
struct ModelRow: View {
    let entry: LocalModelEntry
    let state: DownloadState
    var isDefault = false
    /// An extra status line, such as "Recommended for this iPhone".
    var note: String?

    @ScaledMetric(relativeTo: .body) private var logoSize: CGFloat = 22

    var body: some View {
        ListRow(entry.descriptor.shortName, secondary: secondary) {
            ModelLogo(brand: ModelBrand.resolve(entry.descriptor), size: logoSize)
        } accessory: {
            if isDefault { DefaultBadge() }
            progress
        }
    }

    private var secondary: Text {
        let status = statusParts
        let detail = Text(HubListOptions.detailLine(entry))
        guard let first = status.first else { return detail }
        let line = status.dropFirst().reduce(first) { $0 + Text(" · ") + $1 }
        return detail + Text("\n") + line
    }

    private var statusParts: [Text] {
        var parts: [Text] = []
        if let note { parts.append(Text(note).foregroundStyle(.tint)) }
        if let fit = HubListOptions.fitStatus(entry, device: DeviceName.current) {
            parts.append(Text(fit).foregroundStyle(ModelStatusColor.fit(entry)))
        }
        parts += entry.badges.map { Text($0.label).foregroundStyle(ModelStatusColor.badge($0.tone)) }
        switch state {
        case .downloading(let progress): parts.append(Text(progressText("Downloading", progress)))
        case .paused(let progress): parts.append(Text(progressText("Paused", progress)))
        case .verifying: parts.append(Text("Verifying"))
        case .failed(let message): parts.append(Text(message).foregroundStyle(.red))
        case .notInstalled, .installed: break
        }
        if entry.isDeprecated { parts.append(Text("Older model, try \(entry.replacementName ?? "a newer one")")) }
        return parts
    }

    private func progressText(_ label: String, _ progress: Double?) -> String {
        progress.map { "\(label) \(HubLogic.percent($0))" } ?? label
    }

    @ViewBuilder
    private var progress: some View {
        switch state {
        case .downloading(let value?), .paused(let value?):
            // A bar, not the circular style: on iOS that draws a spinner whatever the value, next to "Downloading 42%".
            ProgressView(value: min(max(value, 0), 1))
                .frame(width: 56)
                .accessibilityLabel("Download progress")
        case .downloading(.none), .paused(.none), .verifying:
            ProgressView()
        case .notInstalled, .installed, .failed:
            EmptyView()
        }
    }
}
