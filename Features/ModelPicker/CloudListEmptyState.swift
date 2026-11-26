import SwiftUI

/// Why a signed-in AnyRouter list shows nothing. A failed load and a list with nothing usable must not look the same
/// as "no models", because the first one has a way out (Retry) and the second one is not an error.
enum CloudEmptyReason: Equatable {
    case loading
    case failed(String)
    /// The catalog loaded, but nothing in it can be used and the filter hides what needs a key.
    case nothingUsable(count: Int)
    case none

    static func reason(models: [ModelDescriptor], failure: String?, isLoading: Bool) -> CloudEmptyReason {
        if isLoading { return .loading }
        if let failure { return .failed(failure) }
        let count = models.filter { $0.source == .anyrouter }.count
        return count > 0 ? .nothingUsable(count: count) : .none
    }
}

/// The empty AnyRouter list, signed in, with nothing searched or filtered.
struct CloudListEmptyState: View {
    let reason: CloudEmptyReason
    let retry: () -> Void

    var body: some View {
        switch reason {
        case .loading:
            ProgressView("Loading models…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Could not load cloud models", systemImage: "exclamationmark.icloud")
            } description: {
                Text(message)
            } actions: {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("cloud-list.retry")
            }
        case .nothingUsable(let count):
            ContentUnavailableView {
                Label("No models you can use yet", systemImage: "cloud")
            } description: {
                Text("AnyRouter lists \(count) models. Models that need your own provider key are hidden. Search to find them, or turn that filter off.")
            }
        case .none:
            ContentUnavailableView("No cloud models", systemImage: "cloud")
        }
    }
}

/// A failed refresh while an older list is still showing: the list stays, the reason and Retry sit on top.
struct CloudListStaleNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Section {
            Label("Could not refresh the list. Showing the last one. \(message)", systemImage: "exclamationmark.icloud")
            Button("Retry", action: retry).accessibilityIdentifier("cloud-list.retry")
        }
    }
}
