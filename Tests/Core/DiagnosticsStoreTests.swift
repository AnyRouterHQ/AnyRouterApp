import Foundation
import Testing
@testable import AnyRouter

struct DiagnosticsStoreTests {
    private func store(limit: Int = 20) -> DiagnosticsStore {
        DiagnosticsStore(directory: makeTempDirectory().appending(path: "Diagnostics"), limit: limit)
    }

    private func payload(_ keys: [String: [Int]]) -> Data {
        try! JSONSerialization.data(withJSONObject: keys)
    }

    @Test func classifyReadsTheDiagnosticArrays() {
        #expect(DiagnosticKind.classify(diagnostics: payload(["crashDiagnostics": [1]])) == .crash)
        #expect(DiagnosticKind.classify(diagnostics: payload(["hangDiagnostics": [1]])) == .hang)
        #expect(DiagnosticKind.classify(diagnostics: payload(["cpuExceptionDiagnostics": [1]])) == .cpu)
        #expect(DiagnosticKind.classify(diagnostics: payload(["diskWriteExceptionDiagnostics": [1]])) == .disk)
    }

    @Test func crashWinsOverHangAndEmptyArraysCountForNothing() {
        #expect(DiagnosticKind.classify(diagnostics: payload(["hangDiagnostics": [1], "crashDiagnostics": [1]])) == .crash)
        #expect(DiagnosticKind.classify(diagnostics: payload(["crashDiagnostics": [], "hangDiagnostics": [1]])) == .hang)
        #expect(DiagnosticKind.classify(diagnostics: payload([:])) == .diagnostic)
        #expect(DiagnosticKind.classify(diagnostics: Data("not json".utf8)) == .diagnostic)
    }

    @Test func everyKindHasATitle() {
        #expect(DiagnosticKind.allCases.map(\.title) == [
            "Crash", "Hang", "CPU exception", "Disk write exception", "Diagnostic", "Metrics", "Model list error", "Model load",
        ])
    }

    @Test func savedPayloadsListNewestFirstWithKindAndDate() throws {
        let s = store()
        #expect(s.list().isEmpty, "a store that was never written to lists nothing")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let crash = payload(["crashDiagnostics": [1]])
        #expect(try s.saveDiagnostics(crash, now: t0) == .crash)
        try s.saveMetrics(Data("{}".utf8), now: t0.addingTimeInterval(60))
        let records = s.list()
        #expect(records.map(\.kind) == [.metric, .crash])
        #expect(records.map(\.date) == [t0.addingTimeInterval(60), t0])
        #expect(try Data(contentsOf: records[1].url) == crash, "the share link points at the stored JSON")
    }

    @Test func onlyTheNewestPayloadsAreKept() throws {
        let s = store(limit: 3)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<5 { try s.saveMetrics(Data("{\"i\":\(i)}".utf8), now: t0.addingTimeInterval(Double(i))) }
        let records = s.list()
        #expect(records.count == 3)
        #expect(records.map(\.date) == [4, 3, 2].map { t0.addingTimeInterval(Double($0)) })
    }

    @Test func theDefaultLimitIsTwenty() throws {
        #expect(DiagnosticsStore.defaultLimit == 20)
        let s = DiagnosticsStore(directory: makeTempDirectory().appending(path: "Diagnostics"))
        #expect(s.limit == 20)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<22 { try s.saveMetrics(Data("{}".utf8), now: t0.addingTimeInterval(Double(i))) }
        #expect(s.list().count == 20)
    }

    @Test func theDefaultFolderIsDiagnosticsInApplicationSupport() {
        let s = DiagnosticsStore()
        #expect(s.directory == URL.applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory))
    }

    @Test func samePayloadsInTheSameMillisecondDoNotOverwriteEachOther() throws {
        let s = store()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try s.saveMetrics(Data("{}".utf8), now: now)
        try s.saveMetrics(Data("{}".utf8), now: now)
        #expect(s.list().count == 2)
    }

    @Test func aModelListFailureIsKeptWithItsSourceAndReason() throws {
        let s = store()
        try s.saveModelListFailure(source: "anyrouter", message: "No answer after 20 seconds.", now: Date(timeIntervalSince1970: 1_800_000_000))
        try s.saveMetrics(Data("{}".utf8), now: Date(timeIntervalSince1970: 1_800_000_060))
        let records = s.list()
        #expect(records.map(\.kind) == [.metric, .modelList])
        #expect(s.modelListMessage(of: records[1]) == "anyrouter: No answer after 20 seconds.")
        #expect(s.modelListMessage(of: records[0]) == nil, "only model list records carry a message")
        try Data("not json".utf8).write(to: records[1].url)
        #expect(s.modelListMessage(of: records[1]) == nil, "a file that does not read gives no message")
    }

    @Test func foreignFilesInTheFolderAreIgnored() throws {
        let s = store()
        try s.saveMetrics(Data("{}".utf8))
        for name in ["notes.txt", "1-bogus-abcd1234.json", "abc-crash-abcd1234.json", "1-crash.json"] {
            try Data("x".utf8).write(to: s.directory.appending(path: name))
        }
        #expect(s.list().count == 1)
    }

    @Test func exitCountsComeFromTheNewestMetricsReportByPhaseAndReason() throws {
        let s = store()
        #expect(s.lastExitCounts().isEmpty, "no metrics report yet")
        let old: [String: Any] = ["applicationExitMetrics": ["foregroundExitData": ["cumulativeAppWatchdogExitCount": 9] as [String: Any]] as [String: Any]]
        let new: [String: Any] = ["applicationExitMetrics": [
            "foregroundExitData": [
                "cumulativeMemoryResourceLimitExitCount": 2, "cumulativeNormalAppExitCount": 0, "cumulativeCPUResourceLimitExitCount": 1,
            ] as [String: Any],
            "backgroundExitData": ["cumulativeMemoryPressureExitCount": 3, "someOtherKey": 5, "cumulativeBadAccessExitCount": "x"] as [String: Any],
        ] as [String: Any]]
        try s.saveMetrics(try JSONSerialization.data(withJSONObject: old), now: Date(timeIntervalSince1970: 1_800_000_000))
        try s.saveMetrics(try JSONSerialization.data(withJSONObject: new), now: Date(timeIntervalSince1970: 1_800_000_060))
        try s.saveModelListFailure(source: "x", message: "y", now: Date(timeIntervalSince1970: 1_800_000_120))
        #expect(s.lastExitCounts() == [
            AppExitCount(phase: "Foreground", reason: "CPU resource limit", count: 1),
            AppExitCount(phase: "Foreground", reason: "Memory resource limit", count: 2),
            AppExitCount(phase: "Background", reason: "Memory pressure", count: 3),
        ], "zero counts, other keys and non-numbers are left out; an older report is not read")
        #expect(DiagnosticsStore.exitCounts(inMetrics: Data("not json".utf8)).isEmpty)
    }

    @Test func camelCaseReasonsReadAsSentences() {
        #expect(DiagnosticsStore.sentence(fromCamelCase: "AppWatchdog") == "App watchdog")
        #expect(DiagnosticsStore.sentence(fromCamelCase: "CPUResourceLimit") == "CPU resource limit")
        #expect(DiagnosticsStore.sentence(fromCamelCase: "BackgroundURLSessionCompletionTimeout") == "Background URL session completion timeout")
        #expect(DiagnosticsStore.sentence(fromCamelCase: "") == "")
    }
}
