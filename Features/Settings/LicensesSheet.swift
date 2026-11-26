import SwiftUI

struct LicensesSheet: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(LicenseNotice.all) { notice in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(notice.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(ARColor.foreground)
                            ForEach(notice.copyright, id: \.self) { SettingsText($0) }
                            SettingsText(notice.license)
                            if let url = URL(string: notice.url) {
                                Link(notice.url, destination: url).font(.arXS)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .arCard(radius: ARTheme.radiusLarge)
                    }
                }
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.bottom, 24)
            }
        }
        .background(ARColor.background.ignoresSafeArea())
    }
}
