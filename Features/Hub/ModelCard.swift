import SwiftUI

/// Hub model card: name, size, description, tags and one action.
struct ModelCard: View {
    let title: String
    let sizeText: String?
    let summary: String
    let tags: [String]
    var badges: [ModelBadge] = []
    var fit: ModelFit = .unknown
    var fitDetail: FitDetail?
    var state: DownloadState = .notInstalled
    var unavailableReason: String?
    var leadingIcon: String?
    var onDownload: (() -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDelete: (() -> Void)?
    /// Shown on a loaded model: app memory and what is left.
    var memoryNote: String?
    var onUnload: (() -> Void)?

    @State private var confirmsDownload = false

    private var device: String { DeviceName.current }
    private var downloadWarning: String? {
        FitText.downloadWarning(fitDetail, sizeText: sizeText, device: device)
    }

    /// A model that will not fit asks first. Everything else downloads at once.
    private func requestDownload() {
        if downloadWarning != nil { confirmsDownload = true } else { onDownload?() }
    }

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
            if let fitDetail {
                Text(FitText.needs(fitDetail) + (fitDetail.isEstimate ? " (estimate)" : ""))
                    .font(.arSM).foregroundStyle(ARColor.mutedForeground)
            }
            FlowTags(tags: tags, badges: badges, fit: fit, fitLabel: fitDetail.flatMap { FitText.badge($0, device: device) })
            if let fitDetail, let explanation = FitText.explanation(fitDetail, device: device) {
                Text(explanation).font(.arXS).foregroundStyle(fitDetail.verdict == .wontFit ? ARColor.destructive : ARColor.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            actions
        }
        .confirmationDialog("Download anyway?", isPresented: $confirmsDownload, titleVisibility: .visible) {
            Button("Download anyway", role: .destructive) { onDownload?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(downloadWarning ?? "")
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
            if onDownload != nil { Button("Download") { requestDownload() }.buttonStyle(.arFilled) }
        case .failed(let message):
            Text(message).font(.arXS).foregroundStyle(ARColor.destructive)
            if onDownload != nil { Button("Retry") { requestDownload() }.buttonStyle(.arFilled) }
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
            if let memoryNote {
                Text(memoryNote).font(.arXS).foregroundStyle(ARColor.mutedForeground)
            }
            HStack(spacing: 8) {
                if let onUnload { Button("Unload") { onUnload() }.buttonStyle(.arSecondary) }
                if let onDelete { Button("Delete") { onDelete() }.buttonStyle(.arDestructive) }
            }
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
    let badges: [ModelBadge]
    let fit: ModelFit
    /// The fit badge text when the card has the numbers behind it ("Runs well", "Short context", ...).
    var fitLabel: String?

    private func tint(_ tone: ModelBadge.Tone) -> Color {
        switch tone {
        case .neutral: ARColor.mutedForeground
        case .info: ARColor.accent
        case .success: .green
        case .warning: .orange
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(badges, id: \.self) { ARChip(text: $0.label, tint: tint($0.tone)) }
            ForEach(tags.prefix(4), id: \.self) { ARChip(text: $0) }
            switch fit {
            case .fits: ARChip(text: fitLabel ?? "fits", tint: .green)
            case .tight: ARChip(text: fitLabel ?? "tight fit", tint: .orange)
            case .wontFit: ARChip(text: fitLabel ?? "too large", tint: ARColor.destructive)
            case .unknown: EmptyView()
            }
            Spacer(minLength: 0)
        }
    }
}
