import SwiftUI

struct LicensesSheet: View {
    var body: some View {
        List(LicenseNotice.all) { notice in
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.name).font(.headline)
                ForEach(notice.copyright, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                Text(notice.license).font(.subheadline).foregroundStyle(.secondary)
                if let url = URL(string: notice.url) {
                    Link(notice.url, destination: url).font(.footnote)
                }
            }
        }
    }
}
