import SwiftUI

/// Hub model card (Atomic hub): name, size, description, tags and one action.
struct ModelCard: View {
    let title: String
    let sizeText: String?
    let summary: String
    let tags: [String]
    var fit: ModelFit = .unknown
    var state: DownloadState = .notInstalled
    var unavailableReason: String?
    var leadingIcon: String?
    var onDownload: (() -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let leadingIcon { Image(systemName: leadingIcon).foregroundStyle(ARColor.foreground) }
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ARColor.foreground)
                Spacer(minLength: 8)
                if let sizeText { Text("· \(sizeText)").font(.arSM).foregroundStyle(ARColor.mutedForeground) }
            }
            Text(summary).font(.arSM).foregroundStyle(ARColor.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
            FlowTags(tags: tags, fit: fit)
            actions
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .arCard(radius: ARTheme.radiusLarge)
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .notInstalled where unavailableReason != nil:
            Text(unavailableReason ?? "").font(.arXS).foregroundStyle(ARColor.mutedForeground)
        case .notInstalled:
            if let onDownload { Button("Download") { onDownload() }.buttonStyle(.arFilled) }
        case .failed(let message):
            Text(message).font(.arXS).foregroundStyle(ARColor.destructive)
            if let onDownload { Button("Retry") { onDownload() }.buttonStyle(.arFilled) }
        case .downloading(let progress):
            progressRow(label: "Downloading", progress: progress)
            HStack(spacing: 8) {
                if let onPause { Button("Pause") { onPause() }.buttonStyle(.arSecondary) }
                if let onCancel { Button("Cancel") { onCancel() }.buttonStyle(.arDestructive) }
            }
        case .paused(let progress):
            progressRow(label: "Paused", progress: progress)
            HStack(spacing: 8) {
                if let onResume { Button("Resume") { onResume() }.buttonStyle(.arFilled) }
                if let onCancel { Button("Cancel") { onCancel() }.buttonStyle(.arDestructive) }
            }
        case .verifying:
            HStack(spacing: 8) { ProgressView(); Text("Verifying").font(.arSM).foregroundStyle(ARColor.mutedForeground) }
        case .installed:
            if let onDelete { Button("Delete") { onDelete() }.buttonStyle(.arDestructive) }
        }
    }

    private func progressRow(label: String, progress: Double?) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(label).font(.arSM).foregroundStyle(ARColor.foreground)
                Spacer()
                Text(HubLogic.percent(progress)).font(.arSM).foregroundStyle(ARColor.mutedForeground)
            }
            if let progress {
                ProgressView(value: min(max(progress, 0), 1)).tint(ARColor.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(ARColor.accent)
            }
        }
    }
}

/// Wrapping row of tag chips plus the device-fit badge.
private struct FlowTags: View {
    let tags: [String]
    let fit: ModelFit

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags.prefix(4), id: \.self) { ARChip(text: $0) }
            switch fit {
            case .fits: ARChip(text: "fits", tint: .green)
            case .tight: ARChip(text: "tight fit", tint: .orange)
            case .wontFit: ARChip(text: "too large", tint: ARColor.destructive)
            case .unknown: EmptyView()
            }
            Spacer(minLength: 0)
        }
    }
}
