import Foundation

enum FitFormat {
    /// Decimal gigabytes with one decimal ("8.1 GB"), megabytes below one gigabyte ("620 MB"). Matches the file sizes the Hub shows.
    static func gigabytes(_ bytes: Int64) -> String {
        if bytes < 1_000_000_000 { return "\(max(0, bytes) / 1_000_000) MB" }
        return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
