import Foundation
import Testing
@testable import AnyRouter

@MainActor
struct MemorySettingsDefaultsTests {
    @Test func defaultsAreWhatTheDesignSays() {
        let settings = AppSettings(defaults: testDefaults())
        #expect(settings.useMemory)
        #expect(settings.saveMemoriesAutomatically)
        #expect(!settings.deviceMemoriesInCloudChats, "memories from on-device chats stay off cloud models until the user allows it")
    }

    @Test func eachSwitchIsKeptAcrossInstances() {
        let defaults = testDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.useMemory = false
        settings.saveMemoriesAutomatically = false
        settings.deviceMemoriesInCloudChats = true
        let again = AppSettings(defaults: defaults)
        #expect(!again.useMemory && !again.saveMemoriesAutomatically && again.deviceMemoriesInCloudChats)
    }
}
