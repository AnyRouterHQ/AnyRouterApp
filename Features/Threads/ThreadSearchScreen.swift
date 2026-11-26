import SwiftData
import SwiftUI

/// Full-screen chat search: the system search field on top, the conversation list below.
/// Blank shows the latest chats; typing replaces them with matches and the text around each match.
struct ThreadSearchScreen: View {
    @Environment(ShellModel.self) private var shell
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ThreadRecord.updatedAt, order: .reverse) private var threads: [ThreadRecord]

    @State private var query = ""
    /// True from the first frame, so the keyboard is up as soon as the screen is.
    @State private var isSearching = false
    @State private var editing = ThreadEditing()

    private var isBlank: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let results = ThreadSearchLogic.results(in: threads, query: query)
        NavigationStack {
            List {
                if isBlank {
                    Section("Recents") { rows(results) }
                } else {
                    rows(results)
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.immediately)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier("search.close")
                }
            }
            .overlay {
                if results.isEmpty {
                    if isBlank {
                        ContentUnavailableView("No chats yet", systemImage: "bubble.left")
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .threadEditingDialogs($editing)
        }
        .onAppear { isSearching = true }
    }

    private func rows(_ results: [ThreadSearchLogic.Hit]) -> some View {
        ForEach(results) { hit in
            Button { shell.openFromSearch(threadID: hit.thread.id) } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.thread.title).lineLimit(1)
                        if let snippet = hit.snippet {
                            Text(snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                } icon: {
                    Image(systemName: hit.thread.isPinned ? "pin.fill" : "bubble.left")
                }
            }
            .foregroundStyle(.primary)
            .threadActions(hit.thread, editing: $editing)
        }
    }
}

#Preview("Search") {
    let container = try! ModelContainer.anyRouter(inMemory: true)
    for (i, title) in ["Trip to Lisbon", "Swift concurrency", "Recipe ideas"].enumerated() {
        container.mainContext.insert(ThreadRecord(title: title, isPinned: i == 0))
    }
    return ThreadSearchScreen()
        .environment(ShellModel())
        .modelContainer(container)
}
