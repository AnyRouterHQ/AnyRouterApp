import SwiftUI

/// The models the picker cannot offer now, each with one line saying why. A row with a fix (sign in, get credits, add a key,
/// browse) is a button; the others are plain rows. Pushed from the "Not available" row of a tab.
struct UnavailableModelsList: View {
    let items: [PickerUnavailableModel]
    /// "iPhone" or "iPad", for reasons that name the device.
    let device: String
    let onFix: (PickerUnavailableModel, ModelUnavailableReason.Fix) -> Void

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    // The id goes on the outermost element: inside a Button, the row's own id is folded into the button
                    // and lost, so UI tests and VoiceOver tools could not find a fixable row (verify-ui 46150715558).
                    Group {
                        if let fix = item.reason.fix {
                            Button { onFix(item, fix) } label: { UnavailableModelRow(item: item, device: device) }
                                .buttonStyle(.plain)
                                .accessibilityHint(fix.title)
                        } else {
                            UnavailableModelRow(item: item, device: device)
                        }
                    }
                    .accessibilityIdentifier("unavailable-row.\(item.model.id)")
                }
            } footer: {
                Text("Tap a model to fix what is in the way, where there is a fix.")
            }
        }
        .navigationTitle("Not available")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("model-picker.not-available-list")
    }
}

private struct UnavailableModelRow: View {
    let item: PickerUnavailableModel
    let device: String

    @ScaledMetric(relativeTo: .body) private var logoSize: CGFloat = 26

    var body: some View {
        HStack(spacing: 12) {
            ModelLogo(brand: ModelBrand.resolve(item.model), size: logoSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(PickerRow.title(item.model)).font(.body)
                Text(item.reason.text(device: device)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
