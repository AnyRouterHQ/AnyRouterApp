import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct ThreadTitleSourceTests {
    @Test func aChatStoredBeforeTitleSourcesExistedCountsAsTheUsersAndIsKeptAsIs() throws {
        let container = try ModelContainer.anyRouter(inMemory: true)
        let old = ThreadRecord(title: "Old chat")
        // Rows written before the column existed read back with no value.
        old.titleSourceRaw = nil
        container.mainContext.insert(old)
        try container.mainContext.save()

        let fetched = try ModelContext(container).fetch(FetchDescriptor<ThreadRecord>())
        #expect(fetched.map(\.title) == ["Old chat"])
        #expect(fetched.first?.titleSourceRaw == nil)
        #expect(fetched.first?.titleSource == .user, "a generated title must not overwrite a name the person may have chosen")
    }

    @Test func eachSourceSurvivesASaveAndFetch() throws {
        let container = try ModelContainer.anyRouter(inMemory: true)
        for (index, source) in [TitleSource.firstMessage, .generated, .user].enumerated() {
            let thread = ThreadRecord(title: "T\(index)")
            thread.titleSource = source
            container.mainContext.insert(thread)
        }
        try container.mainContext.save()
        let fetched = try ModelContext(container).fetch(FetchDescriptor<ThreadRecord>(sortBy: [SortDescriptor(\.title)]))
        #expect(fetched.map(\.titleSource) == [.firstMessage, .generated, .user])
    }

    @Test func anUnknownStoredValueCountsAsTheUsers() {
        let thread = ThreadRecord(title: "T")
        thread.titleSourceRaw = "from-a-newer-app"
        #expect(thread.titleSource == .user)
    }
}
