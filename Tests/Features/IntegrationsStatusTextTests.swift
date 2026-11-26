import Testing
@testable import AnyRouter

struct IntegrationsStatusTextTests {
    @Test func statusLinesMatchTheServerRows() {
        #expect(IntegrationsLogic.statusText(.connected, toolCount: 3) == "Connected · 3 tools")
        #expect(IntegrationsLogic.statusText(.connected, toolCount: 1) == "Connected · 1 tool")
        #expect(IntegrationsLogic.statusText(.needsSignIn, toolCount: 0) == "Sign in to connect")
        #expect(IntegrationsLogic.statusText(.connecting, toolCount: 4) == "Connecting")
        #expect(IntegrationsLogic.statusText(.idle, toolCount: 0) == "Not connected")
        #expect(IntegrationsLogic.statusText(.failed("Timed out"), toolCount: 0) == "Timed out")
    }
}
