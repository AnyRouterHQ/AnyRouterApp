import Foundation
import Observation
import SwiftData
import UIKit

/// Offline sample data for screenshots and UI tests. Active only with the launch argument `-ARDemoData YES`.
/// Optional flags: `-ARDemoParts YES` (a reply with reasoning, tools, files, a subagent and a compacted history), `-ARDemoSources YES` (a markdown reply that cites five pages), `-ARReplyTextStep -2...3`, `-ARReplyFont serif|rounded`, `-ARDemoSignedOut YES`, `-ARDemoOnboarding YES`, `-ARDemoTools YES` (a thread with a web search step), `-ARAppearance light|dark`.
/// `-ARDemoKeepSettings YES` keeps settings from the previous launch, to test persistence.
/// `-ARDemoMemories YES` seeds a few memories for Settings > Memory.
/// `-ARDemoAwaySeconds N` records a trip to the background N seconds before launch.
enum DemoData {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "ARDemoData") }
    private static var signedOut: Bool { UserDefaults.standard.bool(forKey: "ARDemoSignedOut") }
    private static var onboarding: Bool { UserDefaults.standard.bool(forKey: "ARDemoOnboarding") }

    // Performance fixtures (UITests/PerformanceTests.swift). All off unless the argument is given.
    /// `-ARDemoLongThread 200`: one extra thread with that many messages, opened at launch.
    private static var longThreadMessages: Int { UserDefaults.standard.integer(forKey: "ARDemoLongThread") }
    /// `-ARDemoManyModels 500`: that many extra cloud models.
    private static var extraModels: Int { UserDefaults.standard.integer(forKey: "ARDemoManyModels") }
    /// `-ARDemoCloudDelay 5`: seconds before the cloud engine returns its model list.
    private static var cloudDelay: Int { UserDefaults.standard.integer(forKey: "ARDemoCloudDelay") }
    /// `-ARDemoStream 1000@50`: every demo reply streams that many tokens at that many per second.
    static var stream: (tokens: Int, perSecond: Int)? {
        guard let raw = UserDefaults.standard.string(forKey: "ARDemoStream") else { return nil }
        let parts = raw.split(separator: "@").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return (parts[0], parts[1])
    }

    /// Fixed id so the shell can open the long thread without tapping through the sidebar.
    private static let longThreadID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11C") ?? UUID()
    /// Thread the shell selects at launch, or nil.
    static var initialThreadID: UUID? { isEnabled && longThreadMessages > 0 ? longThreadID : nil }
    private static var tools: Bool { UserDefaults.standard.bool(forKey: "ARDemoTools") }
    private static var sources: Bool { UserDefaults.standard.bool(forKey: "ARDemoSources") }
    private static var parts: Bool { UserDefaults.standard.bool(forKey: "ARDemoParts") }

    /// Text of the demo search result, read by the UI tests.
    static let demoSearchResult = "Swift 7 adds typed throws everywhere and faster builds."

    /// `-ARDemoAttachFile YES` stages a small text file under the composer, so the UI test can see the chip
    /// without driving the system file picker.
    static var attachesSampleFile: Bool { isEnabled && UserDefaults.standard.bool(forKey: "ARDemoAttachFile") }

    /// `-ARDemoDecisionPhoto YES` puts a drawn receipt in a decision's photo row: the Simulator has no camera.
    static var addsDecisionPhoto: Bool { isEnabled && UserDefaults.standard.bool(forKey: "ARDemoDecisionPhoto") }

    static func receiptPhoto() -> Data {
        let size = CGSize(width: 600, height: 800)
        return UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
            UIColor(white: 0.82, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 70, y: 40, width: 460, height: 720))
            let lines = ["CORNER CAFE", "2 flat white   7.00", "1 croissant    2.40", "TOTAL          9.40", "Client meeting"]
            for (index, line) in lines.enumerated() {
                line.draw(at: CGPoint(x: 100, y: 90 + index * 70), withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 28, weight: .regular), .foregroundColor: UIColor.black,
                ])
            }
        }
    }

    /// `-ARDemoClipboard YES` makes the chat offer the clipboard row, so the screenshot test can capture it.
    static var offersClipboard: Bool { isEnabled && UserDefaults.standard.bool(forKey: "ARDemoClipboard") }

    /// The pasteboard the chat watches: the real one, nothing in demo runs, or a copied text with `-ARDemoClipboard`.
    static var pasteboard: any PasteboardProbe {
        if offersClipboard { return DemoPasteboard() }
        if isEnabled { return EmptyPasteboard() }
        return SystemPasteboard()
    }

    /// `-ARDemoStore fresh` keeps the demo chats in a file, emptied at this launch; `keep` opens that file again, so a
    /// UI test can relaunch the app and find its chat. Without it the store is in memory.
    private static func demoStoreURL() throws -> URL? {
        guard let mode = UserDefaults.standard.string(forKey: "ARDemoStore") else { return nil }
        let folder = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "demo-chats.store")
        if mode == "fresh" {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        }
        return url
    }

    /// `-ARDemoFail rateLimited`, `offline` or `credits`: every reply fails with that engine error.
    static var replyError: (any Error)? {
        switch UserDefaults.standard.string(forKey: "ARDemoFail") {
        case "rateLimited": return AnyRouterError.http(status: 429, message: "Rate limit exceeded for this model. Retry in 20 s.")
        case "offline": return URLError(.notConnectedToInternet)
        case "credits": return AnyRouterError.http(status: 402, message: "Insufficient credits: 0.00 left.")
        default: return nil
        }
    }

    static func sampleAttachmentURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "notes.txt")
        try? Data("Pick up the keys.\nCall the bank on Monday.\n".utf8).write(to: url)
        return url
    }

    /// In-memory store with five sample threads, or the file of `-ARDemoStore` (seeded once).
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer.anyRouter(inMemory: true, storeURL: try demoStoreURL())
        let context = container.mainContext
        // A kept store already holds the chats of the last launch.
        if try context.fetchCount(FetchDescriptor<ThreadRecord>()) > 0 { return container }
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
        insertSwitchThread(in: context, at: now)
        if tools { insertToolThread(in: context, at: now) }
        if sources { insertSourcesThread(in: context, at: now) }
        if parts { insertPartsThread(in: context, at: now) }
        if longThreadMessages > 0 { insertLongThread(into: context, now: now) }
        if memories { try insertMemories(in: context) }
        try context.save()
        return container
    }

    /// `-ARDemoMemories YES`: a few memories for the Settings > Memory screenshots.
    private static var memories: Bool { UserDefaults.standard.bool(forKey: "ARDemoMemories") }

    @MainActor
    private static func insertMemories(in context: ModelContext) throws {
        let store = MemoryStore(context: context)
        let lisbon = try context.fetch(FetchDescriptor<ThreadRecord>()).first { $0.title == "Trip ideas for Lisbon" }
        let now = Date()
        try store.add("My name is Lan.", kind: .profile, now: now.addingTimeInterval(-50))
        try store.add("I live in Ho Chi Minh City.", kind: .profile, now: now.addingTimeInterval(-40))
        try store.add("Short answers. Reply in Vietnamese when I write in Vietnamese.", kind: .preference, now: now.addingTimeInterval(-30))
        try store.add("I am allergic to peanuts.", kind: .note, now: now.addingTimeInterval(-20))
        try store.add("My dog is called Mochi.", kind: .fact, origin: .askedInChat, now: now.addingTimeInterval(-10))
        try store.add("A relaxed 3 day plan for Lisbon: Alfama, Belem, Sintra.", kind: .chatSummary, origin: .extracted,
                      scope: .deviceOnly, sourceThreadID: lisbon?.id, now: now)
    }

    static let switchThreadTitle = "Switch models in a chat"

    /// A thread where the model changed between replies: a free cloud reply, a paid one and a local one. Shows the
    /// footer line for each, the details sheet and the "Switched to" note.
    @MainActor
    private static func insertSwitchThread(in context: ModelContext, at now: Date) {
        let created = now.addingTimeInterval(-60)
        let thread = ThreadRecord(title: switchThreadTitle, createdAt: created, modelID: "anyrouter/openai/gpt-5")
        context.insert(thread)
        func add(_ role: ChatMessage.Role, _ text: String, at offset: Double, name: String? = nil, id: String? = nil,
                 metadata: ResponseMetadata? = nil) {
            let record = MessageRecord(role: role, content: text, createdAt: created.addingTimeInterval(offset),
                                       modelName: name, modelID: id)
            record.metadata = metadata
            context.insert(record)
            record.thread = thread
        }
        add(.user, "Suggest a name for a small router app.", at: 0)
        add(.assistant, "How about Waypoint? Short, clear, and it says what a router does.", at: 5,
            name: "AnyRouter", id: "anyrouter/anyrouter/auto",
            metadata: ResponseMetadata(
                requestID: "req_demo01", servedModelID: "nvidia/nemotron-3.5-bolt-e4b",
                servedModelName: "Nemotron 3.5 Bolt E4B", provider: "NVIDIA", costUSD: 0, promptTokens: 18,
                completionTokens: 41, upstreamLatencyMs: 640, ttftMs: 600, totalMs: 2100))
        add(.user, "Give me three more, more playful.", at: 10)
        add(.assistant, "Hopscotch, Postmark, Zigzag.", at: 15, name: "GPT-5", id: "anyrouter/openai/gpt-5",
            metadata: ResponseMetadata(
                requestID: "req_demo02", servedModelID: "openai/gpt-5", servedModelName: "GPT-5", provider: "OpenAI",
                costUSD: Decimal(string: "0.0004"), promptTokens: 74, completionTokens: 12, cachedTokens: 40,
                upstreamLatencyMs: 880, ttftMs: 700, totalMs: 1300))
        add(.user, "And one that runs on this phone?", at: 20)
        add(.assistant, "Pocketpost. It never leaves the device.", at: 25, name: "Gemma 4 E2B", id: "gguf/demo/gemma-4-e2b.gguf",
            metadata: ResponseMetadata(
                servedModelID: "gguf/demo/gemma-4-e2b.gguf", servedModelName: "Gemma 4 E2B", provider: "On device",
                costUSD: 0, promptTokens: 20, completionTokens: 60, ttftMs: 500, totalMs: 3500))
    }

    /// A finished reply with its response details, never stored. Settings previews draw the real reply row from it.
    @MainActor
    static func sampleReply() -> MessageRecord {
        let record = MessageRecord(
            role: .assistant, content: "A router sends each message to the model that suits it best.",
            modelName: "GPT-5", modelID: "anyrouter/openai/gpt-5")
        record.metadata = ResponseMetadata(
            requestID: "req_preview", servedModelID: "openai/gpt-5", servedModelName: "GPT-5", provider: "OpenAI",
            costUSD: Decimal(string: "0.0004"), promptTokens: 74, completionTokens: 12, cachedTokens: 40,
            upstreamLatencyMs: 880, ttftMs: 700, totalMs: 1300)
        return record
    }

    static let partsThreadTitle = "Reply parts"

    /// A drawn photo and a one-page PDF in the attachments folder, for the cards and the viewer.
    @MainActor
    private static func demoAttachments(forThread id: UUID) -> [ChatAttachment] {
        let store = AttachmentStore.shared
        let size = CGSize(width: 600, height: 400)
        let photo = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemTeal.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 80, y: 60, width: 280, height: 280))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 380, y: 140, width: 140, height: 140))
        }
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let document = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            let text = "Swift actors\n\nAn actor protects its own mutable state: one task runs inside it at a time."
            (text as NSString).draw(
                in: CGRect(x: 48, y: 48, width: 516, height: 300), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        var result: [ChatAttachment] = []
        for (name, type, kind, data, ext) in [
            ("diagram.jpg", "public.jpeg", ChatAttachment.Kind.image, photo, "jpg"),
            ("Actors.pdf", "com.adobe.pdf", ChatAttachment.Kind.pdf, document, "pdf"),
        ] {
            let attachmentID = UUID()
            guard let path = try? store.write(data, id: attachmentID, fileExtension: ext, folder: id.uuidString) else { continue }
            result.append(ChatAttachment(
                id: attachmentID, kind: kind, filename: name, utType: type, byteCount: Int64(data.count), relativePath: path))
        }
        return result
    }

    /// The newest thread: one answer that thought for 12 seconds, searched the web and cited five pages.
    @MainActor
    private static func insertPartsThread(in context: ModelContext, at now: Date) {
        let thread = ThreadRecord(title: partsThreadTitle, createdAt: now.addingTimeInterval(180),
                                  modelID: "anyrouter/anthropic/claude-sonnet-4-6")
        context.insert(thread)
        // Four older messages, folded into a summary: the divider sits between them and the question below.
        var older: [MessageRecord] = []
        for (offset, line) in [
            (ChatMessage.Role.user, "What is structured concurrency?"),
            (.assistant, "Tasks that start and end inside one scope, so no work is left running by accident."),
            (.user, "And what is an actor?"),
            (.assistant, "A type that protects its own mutable state: one task runs inside it at a time."),
        ].enumerated() {
            let record = MessageRecord(role: line.0, content: line.1, createdAt: thread.createdAt.addingTimeInterval(Double(offset - 8)))
            context.insert(record)
            record.thread = thread
            older.append(record)
        }
        if let last = older.last {
            thread.compactions = [Compaction(
                lastMessageID: last.id,
                summary: "The reader asked what structured concurrency and actors are. Structured concurrency keeps tasks inside one scope. An actor guards its mutable state so only one task runs in it at a time.",
                droppedCount: older.count, createdAt: thread.createdAt.addingTimeInterval(-1))]
        }
        let question = MessageRecord(role: .user, content: "Why do Swift actors need await?", createdAt: thread.createdAt)
        let answer = MessageRecord(
            role: .assistant,
            content: "An actor runs one task at a time, so a call from outside may have to **wait its turn**. `await` marks that wait.",
            createdAt: thread.createdAt.addingTimeInterval(20),
            modelName: "Claude Sonnet 4.6", modelID: "anyrouter/anthropic/claude-sonnet-4-6")
        answer.metadata = ResponseMetadata(
            requestID: "req_parts", servedModelID: "anthropic/claude-sonnet-4-6", servedModelName: "Claude Sonnet 4.6",
            provider: "Anthropic", costUSD: Decimal(string: "0.0123"), promptTokens: 1210, completionTokens: 188,
            upstreamLatencyMs: 900, ttftMs: 900, totalMs: 14_000)
        answer.attachments = demoAttachments(forThread: thread.id)
        answer.reasoning = ReasoningTrace(
            text: """
            The question is about isolation. An actor serializes access to its state.
            A caller outside the actor cannot touch the state directly, so the call is asynchronous.
            That is why the compiler asks for await: the call is a suspension point.
            I will check the Swift documentation and then answer in two sentences.
            """,
            durationMs: 12_000)
        context.insert(question)
        context.insert(answer)
        question.thread = thread
        answer.thread = thread
        func step(_ id: String, _ name: String, _ arguments: String, _ result: String) -> ToolStep {
            let call = ToolCall(id: id, name: name, argumentsJSON: arguments)
            return ToolStep(call: call, result: ToolResult(callID: id, name: name, text: result, isError: false))
        }
        var subagent = step(
            "demo-parts-5", SubagentLogic.toolName,
            #"{"title":"Research","model":"anthropic/claude-haiku-4.5","task":"Find two sources on actor isolation."}"#,
            "Two sources agree: calls into an actor from outside are asynchronous because the actor handles one at a time.")
        subagent.children = [
            step("demo-parts-5a", "web_search_exa", #"{"query":"actor isolation"}"#, demoSourcesResult),
            step("demo-parts-5b", "fetch_url", #"{"url":"https://blog.example.net/strict-concurrency"}"#, "Turn the checks on one module at a time."),
            step("demo-parts-5c", "fetch_url", #"{"url":"https://swift.example.net/main-actor"}"#, "Use MainActor for UI state."),
            step("demo-parts-5d", "calculator", #"{"expression":"2*2"}"#, "4"),
        ]
        answer.toolSteps = [
            step("demo-parts-1", "web_search_exa", #"{"query":"swift actor await"}"#, demoSourcesResult),
            step("demo-parts-2", "fetch_url", #"{"url":"https://docs.example.com/swift/concurrency"}"#, "An actor protects its mutable state."),
            step("demo-parts-3", "fetch_url", #"{"url":"https://notes.example.com/sendable"}"#, "Isolation keeps data races out."),
            step("demo-parts-4", "calculator", #"{"expression":"1+1"}"#, "2"),
            subagent,
        ]
    }

    static let sourcesThreadTitle = "Swift actors with sources"

    /// The newest thread: a markdown reply after a web search that found five pages, one of them twice.
    @MainActor
    private static func insertSourcesThread(in context: ModelContext, at now: Date) {
        let thread = ThreadRecord(title: sourcesThreadTitle, createdAt: now.addingTimeInterval(120),
                                  modelID: "anyrouter/anthropic/claude-sonnet-4-6")
        context.insert(thread)
        let question = MessageRecord(role: .user, content: "Explain Swift actors in a few lines, with a small example.",
                                     createdAt: thread.createdAt)
        let answer = MessageRecord(role: .assistant, content: markdownAnswer, createdAt: thread.createdAt.addingTimeInterval(20),
                                   modelName: "Claude Sonnet 4.6", modelID: "anyrouter/anthropic/claude-sonnet-4-6")
        answer.metadata = ResponseMetadata(
            requestID: "req_sources", servedModelID: "anthropic/claude-sonnet-4-6", servedModelName: "Claude Sonnet 4.6",
            provider: "Anthropic", costUSD: Decimal(string: "0.0123"), promptTokens: 1210, completionTokens: 188,
            upstreamLatencyMs: 900, ttftMs: 900, totalMs: 4800)
        context.insert(question)
        context.insert(answer)
        question.thread = thread
        answer.thread = thread
        let call = ToolCall(id: "demo-sources", name: "web_search_exa", argumentsJSON: #"{"query":"swift actors"}"#)
        answer.toolSteps = [ToolStep(
            call: call, result: ToolResult(callID: call.id, name: call.name, text: demoSourcesResult, isError: false))]
    }

    /// The text a search tool returns, the way `WebGrounding.parse` reads it. Reserved example hosts, so nothing is real.
    private static let demoSourcesResult = """
    Title: Concurrency, the actor model
    URL: https://docs.example.com/swift/concurrency
    Highlights:
    An actor protects its mutable state.

    Title: Actors in practice
    URL: https://www.example.org/articles/actors
    Highlights:
    Calls from outside need await.

    Title: Actors in practice (print view)
    URL: https://example.org/articles/actors/
    Highlights:
    The same article, written another way.

    Title: Main actor and UI state
    URL: https://swift.example.net/main-actor
    Highlights:
    Use MainActor for UI state.

    Title: Sendable and isolation
    URL: https://notes.example.com/sendable
    Highlights:
    Isolation keeps data races out.

    Title: Migrating to strict concurrency
    URL: https://blog.example.net/strict-concurrency
    Highlights:
    Turn the checks on one module at a time.
    """

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
        if !UserDefaults.standard.bool(forKey: "ARDemoKeepSettings") { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.hasOnboarded = !onboarding
        if UserDefaults.standard.object(forKey: "ARReplyTextStep") != nil {
            settings.replyTextStep = UserDefaults.standard.integer(forKey: "ARReplyTextStep")
        }
        if let raw = UserDefaults.standard.string(forKey: "ARReplyFont"), let font = ReplyFont(rawValue: raw) {
            settings.replyFont = font
        }
        // `-ARDemoAwaySeconds 120`: the app went to the background that long ago, so a launch is a return after time away.
        if UserDefaults.standard.object(forKey: "ARDemoAwaySeconds") != nil {
            settings.lastBackgroundedAt = .now.addingTimeInterval(-Double(UserDefaults.standard.integer(forKey: "ARDemoAwaySeconds")))
        }
        if let raw = UserDefaults.standard.string(forKey: "ARAppearance"),
           let appearance = AppSettings.Appearance(rawValue: raw) {
            settings.appearance = appearance
        }
        let cloud = signedOut || onboarding ? [] : cloudModels + extraCloudModels
        registry.register(DemoEngine(source: .apple, models: [descriptor("apple/foundation", .apple, "Apple Intelligence")]))
        registry.register(DemoEngine(source: .gguf, models: onboarding ? [] : installedLocal))
        registry.register(DemoEngine(source: .anyrouter, models: cloud, listDelay: .seconds(cloudDelay)))
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
        // Real AnyRouter models take tool calls, so the @ list offers plugins like Exa in demo data too.
        model.capabilities.insert("tools")
        model.contextLength = context
        model.cloud = CloudInfo(
            pricing: CloudPricing(
                input: input, output: output, cacheRead: nil,
                billing: input == 0 && output == 0 ? .free : .credits),
            availability: .usable, upstreamCount: upstreams, memberCount: members,
            supportsVision: vision, supportsReasoning: reasoning, created: nil, logoURL: nil)
        return model
    }

    private static var extraCloudModels: [ModelDescriptor] {
        (0..<max(extraModels, 0)).map {
            let number = String(format: "%03d", $0 + 1)
            return descriptor("anyrouter/bench/model-\(number)", .anyrouter, "Bench model \(number)")
        }
    }

    /// Alternating user and assistant messages with a mix of paragraphs, lists and code, newest thread first.
    @MainActor
    private static func insertLongThread(into context: ModelContext, now: Date) {
        let thread = ThreadRecord(id: longThreadID, title: "Long thread", createdAt: now.addingTimeInterval(60),
                                  modelID: "apple/foundation")
        context.insert(thread)
        for index in 0..<longThreadMessages {
            let role: ChatMessage.Role = index.isMultiple(of: 2) ? .user : .assistant
            let text = role == .user ? "Question \(index / 2 + 1): how does this part work?" : longAnswer(number: index / 2 + 1)
            let record = MessageRecord(role: role, content: text, createdAt: now.addingTimeInterval(60 + Double(index)))
            context.insert(record)
            record.thread = thread
        }
    }

    private static func longAnswer(number: Int) -> String {
        """
        Answer \(number). The short version: **keep state in one place** and let views read it.

        - First point about the design, with `inline code` in it.
        - Second point, a little longer so the line wraps on a phone screen and the layout has some work to do.

        ```swift
        let value = compute(\(number))
        print(value)
        ```

        That is all there is to it.
        """
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

    private static let localCatalog: [(id: String, name: String, size: Int64, summary: String, tags: [String], fit: ModelFit, family: String)] = [
        ("gguf/Qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q4_K_M.gguf", "Qwen3 0.6B", 484_000_000,
         "Small and fast. Good for quick answers.", ["gguf", "0.6B", "Q4_K_M"], .fits, "qwen3"),
        ("gguf/bartowski/Llama-3.2-1B-Instruct-GGUF/Llama-3.2-1B-Instruct-Q4_K_M.gguf", "Llama 3.2 1B Instruct", 808_000_000,
         "Meta's compact instruction model.", ["gguf", "1B", "Q4_K_M"], .fits, "llama32"),
        ("gguf/ggml-org/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf", "Gemma 3 1B", 806_000_000,
         "Google's small multilingual model.", ["gguf", "1B", "Q4_K_M"], .fits, "gemma3"),
        ("gguf/Qwen/Qwen3-1.7B-GGUF/Qwen3-1.7B-Q4_K_M.gguf", "Qwen3 1.7B", 1_280_000_000,
         "Stronger reasoning, still phone sized.", ["gguf", "1.7B", "Q4_K_M"], .fits, "qwen3"),
        ("gguf/bartowski/Llama-3.2-3B-Instruct-GGUF/Llama-3.2-3B-Instruct-Q4_K_M.gguf", "Llama 3.2 3B Instruct", 2_020_000_000,
         "Best quality of the small Llama models.", ["gguf", "3B", "Q4_K_M"], .tight, "llama32"),
        // The experimental 1-bit mixture-of-experts entry, under a demo repo id (the real one lives in catalog/models.json).
        ("gguf/demo/Inkling-2-Mini-GGUF/Inkling-2-Mini-1bit.gguf", "Inkling 2 Mini", 6_881_463_904,
         "Experimental 1-bit mixture of experts. Streams from storage; best with 16 GB.", ["gguf", "26B", "1-bit"], .tight, "inkling"),
    ]

    private static let familyNames = ["qwen3": "Qwen3", "llama32": "Llama 3.2", "gemma3": "Gemma 3", "inkling": "Inkling 2 Mini"]

    /// Sizes that do not fit the demo device (3.2 GB for models), so Local Models has a Not available list.
    private static let tooBigCatalog: [(id: String, name: String, size: Int64, summary: String)] = [
        ("gguf/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf", "Llama 3.1 8B Instruct", 4_920_000_000,
         "A larger Llama for devices with more memory."),
        ("gguf/Qwen/Qwen3-14B-GGUF/Qwen3-14B-Q4_K_M.gguf", "Qwen3 14B", 9_000_000_000,
         "Strong reasoning, needs a lot of memory."),
    ]

    private static var installedLocal: [ModelDescriptor] {
        localCatalog.prefix(2).map { descriptor($0.id, .gguf, $0.name, size: $0.size) }
    }

    fileprivate static var hubEntries: [LocalModelEntry] {
        let fitting = localCatalog.map {
            LocalModelEntry(descriptor: descriptor($0.id, .gguf, $0.name, size: $0.size, installed: false),
                            summary: $0.summary, tags: $0.tags, fit: $0.fit, isUserAdded: false,
                            familyID: $0.family, familyName: familyNames[$0.family])
        }
        let tooBig = tooBigCatalog.map { model in
            let detail = FitDetail(
                verdict: .wontFit, neededBytes: model.size + 1_200_000_000, budgetBytes: 3_200_000_000, context: 512,
                maxReply: 64, streamsFromStorage: false, isEstimate: false)
            return LocalModelEntry(
                descriptor: descriptor(model.id, .gguf, model.name, size: model.size, installed: false),
                summary: model.summary, tags: ["gguf", "Q4_K_M"], fit: .wontFit, isUserAdded: false, fitDetail: detail)
        }
        return fitting + tooBig
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

/// Canned decision models and answers so the Decisions apps work offline. Each answer fits its question's kind.
struct DemoDecisionsService: DecisionsService {
    func decisionModels() async throws -> [DecisionModel] {
        [DecisionModel(id: "anyrouter/decision", name: "AnyRouter Decision", acceptsImages: false),
         DecisionModel(id: "google/gemini-decision-1", name: "Gemini Decision 1", acceptsImages: true)]
    }

    func run(_ request: DecisionRequest) async throws -> DecisionResult {
        DecisionResult(
            model: request.model,
            answers: request.questions.map {
                DecisionAnswer(id: $0.id, prompt: $0.prompt, outcome: .answered(Self.verdict(for: $0.kind)), citations: [])
            },
            inputTokens: 120, outputTokens: 12, cost: 0, refusal: nil, latency: 0.8)
    }

    private static func verdict(for kind: DecisionQuestion.Kind) -> DecisionAnswer.Verdict {
        switch kind {
        case .yesNo:
            return .init(headline: "Yes", probability: 0.91, options: [.init(label: "Yes", probability: 0.91), .init(label: "No", probability: 0.09)])
        case .choice(let options):
            let shares = [0.68, 0.2, 0.08, 0.04]
            let ranked = options.enumerated().map { DecisionAnswer.Option(label: $1, probability: $0 < shares.count ? shares[$0] : 0.01) }
            return .init(headline: options[0], probability: ranked[0].probability, confidence: 0.8, options: ranked)
        case .rubric(let levels):
            let top = levels.count - 1
            let level = min(top, levels.count * 3 / 4)
            let near = [(level, 0.6), (level - 1, 0.25), (level + 1, 0.15)].filter { (0...top).contains($0.0) }
            return .init(
                headline: String(level), probability: nil, score: Double(level), maxScore: Double(top), note: levels[level],
                confidence: 0.7, options: near.map { .init(label: levels[$0.0], probability: $0.1) })
        }
    }
}

/// Streams a canned reply so the composer works offline.
struct DemoEngine: ChatEngine {
    let source: ModelSource
    let models: [ModelDescriptor]
    /// Wait before `availableModels` returns, to stand in for a slow network.
    var listDelay: Duration = .zero

    func availableModels() async throws -> [ModelDescriptor] {
        if listDelay > .zero { try await Task.sleep(for: listDelay) }
        return models
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            if let error = DemoData.replyError {
                continuation.finish(throwing: error)
                return
            }
            guard let plan = DemoData.stream else {
                continuation.yield(.text("This is a demo reply."))
                continuation.yield(.done(finishReason: "stop"))
                continuation.finish()
                return
            }
            let task = Task {
                let interval = Duration.seconds(1) / plan.perSecond
                for index in 0..<plan.tokens {
                    if Task.isCancelled { break }
                    continuation.yield(.text(Self.token(index)))
                    try? await Task.sleep(for: interval)
                }
                continuation.yield(.done(finishReason: "stop"))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension DemoEngine {
    /// Deterministic text with paragraphs, bullets, bold and a code fence, so the markdown parser has real work.
    static func token(_ index: Int) -> String {
        let block = index % 120
        switch block {
        case 0: return "\n\n- "
        case 1..<20: return "word\(index) "
        case 20: return "\n- "
        case 21..<40: return "item\(index) "
        case 40: return "\n\n**"
        case 41: return "Note"
        case 42: return "** "
        case 43..<70: return "text\(index) "
        case 70: return "\n\n```swift\n"
        case 71..<80: return "let v\(index) = \(index)\n"
        case 80: return "```\n\n"
        default: return "plain\(index) "
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

    func signIn(mode: AuthMode) async throws { state = .signedIn(label: "you@example.com") }
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
