import SwiftUI

struct LicensesSheet: View {
    var body: some View {
        List(LicenseNotice.all) { notice in
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.name).font(.headline)
                ForEach(notice.copyright, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                Text(notice.license).font(.subheadline).foregroundStyle(.secondary)
                if let url = URL(string: notice.url) {
                    // An arrow, so the address reads as a link under the mono tint (HIG audit 2026-11-28 #24).
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Text(notice.url)
                            Image(systemName: "arrow.up.forward").imageScale(.small).accessibilityHidden(true)
                        }
                    }
                    .font(.footnote)
                }
            }
        }
    }
}
