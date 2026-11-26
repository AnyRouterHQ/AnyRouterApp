import Foundation
import Observation
import SwiftData

/// Offline sample data for screenshots and UI tests. Active only with the launch argument `-ARDemoData YES`.
/// Optional flags: `-ARDemoSignedOut YES`, `-ARDemoOnboarding YES`, `-ARAppearance light|dark`.
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "ARDemoData") }
    private static var signedOut: Bool { UserDefaults.standard.bool(forKey: "ARDemoSignedOut") }
    private static var onboarding: Bool { UserDefaults.standard.bool(forKey: "ARDemoOnboarding") }

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
        try context.save()
        return container
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

    private static let cloudModels: [ModelDescriptor] = [
        descriptor("anyrouter/anthropic/claude-sonnet-4-6", .anyrouter, "Claude Sonnet 4.6"),
        descriptor("anyrouter/anthropic/claude-opus-4-5", .anyrouter, "Claude Opus 4.5"),
        descriptor("anyrouter/openai/gpt-5", .anyrouter, "GPT-5"),
        descriptor("anyrouter/openai/gpt-5-mini", .anyrouter, "GPT-5 mini"),
        descriptor("anyrouter/google/gemini-2.5-pro", .anyrouter, "Gemini 2.5 Pro"),
        descriptor("anyrouter/meta-llama/llama-4-maverick", .anyrouter, "Llama 4 Maverick"),
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

    func signIn() async throws { state = .signedIn(label: "you@example.com") }
    func signOut() async { state = .signedOut }
}

/// Fixed catalog: two installed, one downloading at 42%, two not installed.
@MainActor @Observable
final class DemoHub: ModelHubService {
    private(set) var catalog: [LocalModelEntry]
    var lastError: String?
    var remoteCatalogURL = ""
    var usesDevelopmentCatalog = false
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
