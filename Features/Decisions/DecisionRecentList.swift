import SwiftData
import SwiftUI

/// The last runs, in a sheet of their own. A tap puts a run back in its screen.
struct DecisionRecentList: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DecisionRunRecord.createdAt, order: .reverse) private var recent: [DecisionRunRecord]
    /// Called after a run is restored, so the caller can show the screen it belongs to.
    var onRestore: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(recent.prefix(DecisionsLogic.recentLimit)) { record in
                    Button {
                        app.decisions.restore(record)
                        dismiss()
                        onRestore()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(DecisionsLogic.title(forState: record.state)).lineLimit(1)
                            Text(record.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .overlay {
                if recent.isEmpty { ContentUnavailableView("No runs yet", systemImage: "clock.arrow.circlepath") }
            }
            .navigationTitle("Recent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
