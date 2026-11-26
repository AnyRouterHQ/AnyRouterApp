import Foundation
import Observation
import SwiftData

/// Offline sample data for screenshots and UI tests. Active only with the launch argument `-ARDemoData YES`.
/// Optional flags: `-ARDemoSignedOut YES`, `-ARDemoOnboarding YES`, `-ARDemoTools YES` (a thread with a web search step), `-ARAppearance light|dark`.
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "ARDemoData") }
    private static var signedOut: Bool { UserDefaults.standard.bool(forKey: "ARDemoSignedOut") }
    private static var onboarding: Bool { UserDefaults.standard.bool(forKey: "ARDemoOnboarding") }
    private static var tools: Bool { UserDefaults.standard.bool(forKey: "ARDemoTools") }

    /// Text of the demo search result, read by the UI tests.
    static let demoSearchResult = "Swift 7 adds typed throws everywhere and faster builds."

    /// `-ARDemoAttachFile YES` stages a small text file under the composer, so the UI test can see the chip
    /// without driving the system file picker.
    static var attachesSampleFile: Bool { isEnabled && UserDefaults.standard.bool(forKey: "ARDemoAttachFile") }

    static func sampleAttachmentURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "notes.txt")
        try? Data("Pick up the keys.\nCall the bank on Monday.\n".utf8).write(to: url)
        return url
    }

    /// In-memory store with five sample threads.
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer.anyRouter(inMemory: true)
        let context = container.mainContext
        let now = Date()
        let threads: [(String, Bool, String, [(ChatMessage.Role, String)])] = [
            ("Explain Swift actors", false, "anyrouter/anthropic/claude-sonnet-4-6", [
                (.user, "Explain Swift actors in a few lines, with a small example."),
                (.assistant, markdownAnswer),
            ]),
            ("Trip ideas for Lisbon", true, "apple/foundation", [
                (.user, "Give me a relaxed 3 day plan for Lisbon."),
                (.assistant, "Start with Alfama on foot, then take tram 28 in the evening. Day two: Belem and a pastel de nata. Day three: a day trip to Sintra."),
            ]),
            ("Summarize meeting notes", false, "gguf/Qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q4_K_M.gguf", [
                (.user, "Summarize these notes in three bullets."),
                (.assistant, "Launch moves to Friday. Design review is done. Two bugs are left in onboarding."),
            ]),
            ("Rust or Go for a CLI?", false, "anyrouter/openai/gpt-5", [
                (.user, "Rust or Go for a small CLI tool?"),
                (.assistant, "Go gets you a single binary fast. Rust gives tighter control and smaller binaries. For a small tool, pick the one your team knows."),
            ]),
            ("Dinner with chickpeas", false, "apple/foundation", [
                (.user, "What can I cook with chickpeas and spinach?"),
                (.assistant, "Chana saag: simmer chickpeas with spinach, garlic, cumin and tomatoes. Serve with rice."),
            ]),
        ]
        for (index, item) in threads.enumerated() {
            let created = now.addingTimeInterval(-Double(index) * 3600 * 5)
            let thread = ThreadRecord(title: item.0, createdAt: created, isPinned: item.1, modelID: item.2)
            context.insert(thread)
            for (offset, message) in item.3.enumerated() {
                let record = MessageRecord(role: message.0, content: message.1,
                                           createdAt: created.addingTimeInterval(Double(offset) * 20))
                context.insert(record)
                record.thread = thread
            }
        }
        if tools { insertToolThread(in: context, at: now) }
        try context.save()
        return container
    }

    /// The newest thread: one reply that searched the web before answering.
    @MainActor
    private static func insertToolThread(in context: ModelContext, at now: Date) {
        let thread = ThreadRecord(title: "Latest Swift news", createdAt: now.addingTimeInterval(60),
                                  modelID: "anyrouter/anthropic/claude-sonnet-4-6")
        context.insert(thread)
        let question = MessageRecord(role: .user, content: "What is new in Swift 7?", createdAt: thread.createdAt)
        let answer = MessageRecord(role: .assistant, content: "Swift 7 brings typed throws and quicker builds.",
                                   createdAt: thread.createdAt.addingTimeInterval(20))
        context.insert(question)
        context.insert(answer)
        question.thread = thread
        answer.thread = thread
        let call = ToolCall(id: "demo-search", name: "web_search", argumentsJSON: #"{"query":"what is new in Swift 7"}"#)
        answer.toolSteps = [ToolStep(
            call: call,
            result: ToolResult(callID: call.id, name: call.name, text: demoSearchResult, isError: false))]
    }

    /// Replaces the real engines, hub, account and settings with fakes. Nothing here touches the network.
    @MainActor
    static func install(registry: EngineRegistry) -> (settings: AppSettings, models: ModelStore, hub: any ModelHubService, account: any AccountService) {
        let suite = "dev.anyrouter.app.demo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        settings.hasOnboarded = !onboarding
        if let raw = UserDefaults.standard.string(forKey: "ARAppearance"),
           let appearance = AppSettings.Appearance(rawValue: raw) {
            settings.appearance = appearance
        }
        let cloud = signedOut || onboarding ? [] : cloudModels
        registry.register(DemoEngine(source: .apple, models: [descriptor("apple/foundation", .apple, "Apple Intelligence")]))
        registry.register(DemoEngine(source: .gguf, models: onboarding ? [] : installedLocal))
        registry.register(DemoEngine(source: .anyrouter, models: cloud))
        let account: any AccountService = DemoAccount(state: signedOut || onboarding ? .signedOut : .signedIn(label: "you@example.com"))
        return (settings, ModelStore(registry: registry, defaults: defaults), DemoHub(installed: !onboarding), account)
    }

    // MARK: Models

    fileprivate static func descriptor(_ id: String, _ source: ModelSource, _ name: String,
                                       size: Int64? = nil, installed: Bool = true) -> ModelDescriptor {
        ModelDescriptor(id: id, source: source, displayName: name, contextLength: 8192,
                        capabilities: ["chat"], sizeBytes: size, isInstalled: installed)
    }

    private static func cloudDescriptor(
        _ id: String, _ name: String, input: Decimal, output: Decimal, context: Int, upstreams: Int,
        members: Int? = nil, vision: Bool = false, reasoning: Bool = false
    ) -> ModelDescriptor {
        var model = descriptor("anyrouter/\(id)", .anyrouter, name)
        model.contextLength = context
        model.cloud = CloudInfo(
            pricing: CloudPricing(
                input: input, output: output, cacheRead: nil,
                billing: input == 0 && output == 0 ? .free : .credits),
            availability: .usable, upstreamCount: upstreams, memberCount: members,
            supportsVision: vision, supportsReasoning: reasoning, created: nil, logoURL: nil)
        return model
    }

    private static let cloudModels: [ModelDescriptor] = [
        cloudDescriptor("anyrouter/auto", "AnyRouter Auto", input: 0, output: 0, context: 4_194_304,
                        upstreams: 1, members: 7, vision: true),
        cloudDescriptor("anyrouter/free", "AnyRouter Free", input: 0, output: 0, context: 1_048_576,
                        upstreams: 1, members: 5),
        cloudDescriptor("anthropic/claude-sonnet-4-6", "Claude Sonnet 4.6", input: 3, output: 15, context: 1_000_000,
                        upstreams: 35, vision: true, reasoning: true),
        cloudDescriptor("anthropic/claude-opus-4-5", "Claude Opus 4.5", input: 5, output: 25, context: 200_000,
                        upstreams: 28, vision: true, reasoning: true),
        cloudDescriptor("openai/gpt-5", "GPT-5", input: Decimal(string: "1.25")!, output: 10, context: 400_000,
                        upstreams: 26, vision: true, reasoning: true),
        cloudDescriptor("openai/gpt-5-mini", "GPT-5 mini", input: Decimal(string: "0.25")!, output: 2, context: 400_000,
                        upstreams: 22, vision: true),
        cloudDescriptor("google/gemini-2.5-pro", "Gemini 2.5 Pro", input: Decimal(string: "1.25")!, output: 10,
                        context: 1_048_576, upstreams: 18, vision: true, reasoning: true),
        cloudDescriptor("meta-llama/llama-4-maverick", "Llama 4 Maverick", input: Decimal(string: "0.15")!,
                        output: Decimal(string: "0.6")!, context: 1_000_000, upstreams: 9),
    ]

    private static let localCatalog: [(id: String, name: String, size: Int64, summary: String, tags: [String], fit: ModelFit)] = [
        ("gguf/Qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q4_K_M.gguf", "Qwen3 0.6B", 484_000_000,
         "Small and fast. Good for quick answers.", ["gguf", "0.6B", "Q4_K_M"], .fits),
        ("gguf/bartowski/Llama-3.2-1B-Instruct-GGUF/Llama-3.2-1B-Instruct-Q4_K_M.gguf", "Llama 3.2 1B Instruct", 808_000_000,
         "Meta's compact instruction model.", ["gguf", "1B", "Q4_K_M"], .fits),
        ("gguf/ggml-org/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf", "Gemma 3 1B", 806_000_000,
         "Google's small multilingual model.", ["gguf", "1B", "Q4_K_M"], .fits),
        ("gguf/Qwen/Qwen3-1.7B-GGUF/Qwen3-1.7B-Q4_K_M.gguf", "Qwen3 1.7B", 1_280_000_000,
         "Stronger reasoning, still phone sized.", ["gguf", "1.7B", "Q4_K_M"], .fits),
        ("gguf/bartowski/Llama-3.2-3B-Instruct-GGUF/Llama-3.2-3B-Instruct-Q4_K_M.gguf", "Llama 3.2 3B Instruct", 2_020_000_000,
         "Best quality of the small Llama models.", ["gguf", "3B", "Q4_K_M"], .tight),
    ]

    private static var installedLocal: [ModelDescriptor] {
        localCatalog.prefix(2).map { descriptor($0.id, .gguf, $0.name, size: $0.size) }
    }

    fileprivate static var hubEntries: [LocalModelEntry] {
        localCatalog.map {
            LocalModelEntry(descriptor: descriptor($0.id, .gguf, $0.name, size: $0.size, installed: false),
                            summary: $0.summary, tags: $0.tags, fit: $0.fit, isUserAdded: false)
        }
    }

    private static let markdownAnswer = """
    An **actor** protects its own mutable state: only one task runs inside it at a time, so you avoid data races without locks.

    Key points:

    - Access from outside needs `await`, because the call may wait its turn.
    - State is isolated by default; `nonisolated` opts a member out.
    - Use `@MainActor` for UI state.

    ```swift
    actor Counter {
        private var value = 0

        func increment() -> Int {
            value += 1
            return value
        }
    }

    let counter = Counter()
    let next = await counter.increment()
    ```

    Calls from several tasks are queued, so `value` is always updated safely.
    """
}

/// Canned decision models and answers so the Decisions screen works offline.
struct DemoDecisionsService: DecisionsService {
    func decisionModels() async throws -> [DecisionModel] {
        [DecisionModel(id: "anyrouter/decision", name: "AnyRouter Decision"),
         DecisionModel(id: "google/gemini-decision-1", name: "Gemini Decision 1")]
    }

    func run(_ request: DecisionRequest) async throws -> DecisionResult {
        let verdict = DecisionAnswer.Verdict(
            headline: "Yes", probability: 0.91, options: [.init(label: "Yes", probability: 0.91), .init(label: "No", probability: 0.09)])
        return DecisionResult(
            model: request.model,
            answers: request.questions.map { DecisionAnswer(id: $0.id, prompt: $0.prompt, outcome: .answered(verdict), citations: []) },
            inputTokens: 120, outputTokens: 12, cost: 0, refusal: nil, latency: 0.8)
    }
}

/// Streams a canned reply so the composer works offline.
struct DemoEngine: ChatEngine {
    let source: ModelSource
    let models: [ModelDescriptor]

    func availableModels() async throws -> [ModelDescriptor] { models }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.text("This is a demo reply."))
            continuation.yield(.done(finishReason: "stop"))
            continuation.finish()
        }
    }
}

@MainActor @Observable
final class DemoAccount: AccountService {
    private(set) var state: AccountState

    init(state: AccountState) { self.state = state }

    var summary: AccountSummary? {
        guard state.isSignedIn else { return nil }
        return AccountSummary.parse(
            me: Data(#"{"data":{"name":"Ada Lovelace","email":"you@example.com","plan":"pro"}}"#.utf8),
            credits: Data(#"{"balance":12.5,"used":3.25,"free_requests":{"remaining":4,"limit":5}}"#.utf8),
            key: nil)
    }

    func signIn() async throws { state = .signedIn(label: "you@example.com") }
    func signOut() async { state = .signedOut }
    func refreshSummary() async {}
}

/// Fixed catalog: two installed, one downloading at 42%, two not installed.
@MainActor @Observable
final class DemoHub: ModelHubService {
    private(set) var catalog: [LocalModelEntry]
    var lastError: String?
    var remoteCatalogURL = ""
    var usesDevelopmentCatalog = false
    var memoryLimitNote: String?
    private let states: [String: DownloadState]

    init(installed: Bool) {
        let entries = DemoData.hubEntries
        catalog = entries
        var states: [String: DownloadState] = [:]
        if installed {
            states[entries[0].id] = .installed
            states[entries[1].id] = .installed
            states[entries[2].id] = .downloading(progress: 0.42)
        }
        self.states = states
    }

    func reload() async {}
    func refreshCatalog() async {}
    func setUsesDevelopmentCatalog(_ on: Bool) async { usesDevelopmentCatalog = on }
    func downloadState(for modelID: String) -> DownloadState { states[modelID] ?? .notInstalled }
    func download(_ entry: LocalModelEntry) {}
    func pause(modelID: String) {}
    func resume(modelID: String) {}
    func cancel(modelID: String) {}
    func delete(modelID: String) async {}
    func searchRepos(_ query: String) async throws -> [RepoHit] { [] }
    func entries(for hit: RepoHit) async throws -> [LocalModelEntry] { [] }
    func addRepo(_ hit: RepoHit) async throws {}
    func removeUserModel(modelID: String) async {}
    func setRemoteCatalogURL(_ text: String) async throws {}
}
