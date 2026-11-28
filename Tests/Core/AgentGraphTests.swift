import Testing
@testable import AnyRouter

/// The step graph of agent design 1.2, row by row.
struct AgentGraphTests {
    private func next(_ node: AgentNode, _ event: AgentEvent, round: Int = 0, max: Int = 4) -> AgentNode {
        AgentGraph.next(node, on: event, round: round, maxRounds: max)
    }

    @Test func theTableOfTheDesign() {
        #expect(next(.assemble, .fits) == .generate)
        #expect(next(.assemble, .overBudget) == .compact)
        #expect(next(.compact, .compacted) == .assemble)
        #expect(next(.compact, .compactFailed) == .generate, "sent as is when shortening fails")
        #expect(next(.generate, .noCalls) == .finish)
        #expect(next(.generate, .calls) == .act)
        #expect(next(.act, .needsApproval) == .approve)
        #expect(next(.approve, .decided) == .act)
        #expect(next(.act, .resultsIn) == .assemble)
        #expect(next(.finish, .noCalls) == .remember)
        #expect(next(.remember, .fits) == .remember, "remember is the end")
    }

    @Test func callsInTheRoundWithToolsOffAreNotRun() {
        #expect(next(.generate, .calls, round: 3, max: 4) == .act)
        #expect(next(.generate, .calls, round: 4, max: 4) == .finish)
        #expect(next(.generate, .calls, round: 0, max: 0) == .finish, "a run without tools")
    }

    @Test func aFailureOrAStopFinishesFromAnyNode() {
        for node in AgentNode.allCases where node != .finish && node != .remember {
            #expect(next(node, .failed) == .finish)
            #expect(next(node, .stopped) == .finish)
        }
        #expect(next(.finish, .failed) == .remember)
    }

    @Test func anEventANodeDoesNotTakeEndsTheRun() {
        #expect(next(.assemble, .calls) == .finish)
        #expect(next(.act, .fits) == .finish)
        #expect(AgentEvent.allCases.count == 11)
    }
}
