import AVFoundation
import Speech

/// Dictation with the system's on-device recognizers: `SpeechTranscriber` where the locale is supported, else
/// `DictationTranscriber` (the keyboard's models, more locales). No download of ours; the system fetches its language
/// assets. Neither framework detects the language from audio, so with no language asked for it runs up to two candidate
/// locales on the same audio and lets `LanguageArbiter` pick.
@MainActor
final class SystemSpeechToText: SpeechToText {
    let id = VoiceModel.systemID

    /// With no clear leader after this long, take the best one so far.
    static let decisionDeadline: Duration = .seconds(4)

    private enum Transcriber {
        case speech(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var module: any SpeechModule {
            switch self {
            case .speech(let transcriber): transcriber
            case .dictation(let transcriber): transcriber
            }
        }
    }

    private struct Candidate {
        var language: VoiceLanguage
        var transcriber: Transcriber
        var assembler = TranscriptAssembler()
    }

    /// Everything one listening session owns, so `cancel` and `finish` can stop it from outside.
    @MainActor private final class Session {
        var isStopping = false
        var capture: MicrophoneCapture?
        var analyzer: SpeechAnalyzer?
        var input: AsyncStream<AnalyzerInput>.Continuation?
        var task: Task<Void, Never>?
        let out: AsyncThrowingStream<TranscriptEvent, Error>.Continuation

        init(out: AsyncThrowingStream<TranscriptEvent, Error>.Continuation) { self.out = out }

        func stopCapture() {
            capture?.stop()
            capture = nil
            input?.finish()
            input = nil
        }
    }

    private var session: Session?

    // MARK: Support

    func supports(_ language: VoiceLanguage) async -> Bool { await Self.resolve(language) != nil }

    private struct Resolved {
        var locale: Locale
        var usesDictation: Bool
    }

    private static func resolve(_ language: VoiceLanguage) async -> Resolved? {
        let device = Locale.current
        let wanted = VoiceLanguage(device.identifier) == language ? device : language.locale
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) { return Resolved(locale: locale, usesDictation: false) }
        if let locale = await SpeechTranscriber.supportedLocales.first(where: { VoiceLanguage($0.identifier) == language }) {
            return Resolved(locale: locale, usesDictation: false)
        }
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: wanted) { return Resolved(locale: locale, usesDictation: true) }
        if let locale = await DictationTranscriber.supportedLocales.first(where: { VoiceLanguage($0.identifier) == language }) {
            return Resolved(locale: locale, usesDictation: true)
        }
        return nil
    }

    private static func makeTranscriber(_ resolved: Resolved) -> Transcriber {
        if resolved.usesDictation {
            return .dictation(DictationTranscriber(
                locale: resolved.locale, contentHints: [], transcriptionOptions: [.punctuation],
                reportingOptions: [.volatileResults], attributeOptions: []))
        }
        return .speech(SpeechTranscriber(
            locale: resolved.locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
            attributeOptions: [.transcriptionConfidence]))
    }

    /// One to two transcribers: the asked-for language, or the first candidates the system can do.
    private static func plan(_ request: SpeechRequest) async throws -> [Candidate] {
        let wanted = request.language.map { [$0] } ?? (request.candidates.isEmpty ? [VoiceLanguage.device] : request.candidates)
        var plan: [Candidate] = []
        for language in wanted where plan.count < 2 {
            if let resolved = await resolve(language) { plan.append(Candidate(language: language, transcriber: makeTranscriber(resolved))) }
        }
        guard !plan.isEmpty else { throw VoiceError.languageUnavailable(wanted[0]) }
        return plan
    }

    // MARK: Session

    func start(_ request: SpeechRequest) -> AsyncThrowingStream<TranscriptEvent, Error> {
        cancel()
        let (stream, out) = AsyncThrowingStream<TranscriptEvent, Error>.makeStream()
        let session = Session(out: out)
        self.session = session
        session.task = Task { await self.run(request, session) }
        out.onTermination = { @Sendable _ in
            Task { @MainActor in
                if self.session === session { self.cancel() }
            }
        }
        return stream
    }

    func finish() async {
        guard let session else { return }
        session.isStopping = true
        session.stopCapture()
        do {
            try await session.analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            session.out.finish(throwing: error)
        }
        await session.task?.value
    }

    func cancel() {
        guard let session else { return }
        self.session = nil
        session.isStopping = true
        session.stopCapture()
        session.task?.cancel()
        session.out.finish()
        let analyzer = session.analyzer
        Task { await analyzer?.cancelAndFinishNow() }
        VoiceAudioSession.deactivate()
    }

    private func run(_ request: SpeechRequest, _ session: Session) async {
        defer {
            session.stopCapture()
            if self.session === session { self.session = nil }
            VoiceAudioSession.deactivate()
        }
        do {
            var candidates = try await Self.plan(request)
            let modules = candidates.map(\.transcriber.module)
            session.out.yield(.preparing(nil))
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await installation.downloadAndInstall()
            }
            // Stop was tapped while the language assets were still loading.
            if session.isStopping {
                session.out.yield(.final(""))
                session.out.finish()
                return
            }
            let analyzer = SpeechAnalyzer(modules: modules)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
                throw VoiceError.audioFailed("This device cannot transcribe speech.")
            }
            let (inputStream, input) = AsyncStream<AnalyzerInput>.makeStream()
            session.analyzer = analyzer
            session.input = input
            try await analyzer.start(inputSequence: inputStream)

            let (readings, feed) = AsyncStream<(Int, String, Double?, Bool)>.makeStream()
            let readers = candidates.enumerated().map { index, candidate in
                Task { await Self.read(candidate.transcriber, index: index, into: feed) }
            }
            let ender = Task {
                for reader in readers { await reader.value }
                feed.finish()
            }

            try VoiceAudioSession.activateRecording()
            let capture = MicrophoneCapture()
            session.capture = capture
            let out = session.out
            try capture.start(
                target: format,
                onBuffer: { input.yield(AnalyzerInput(buffer: $0)) },
                onLevel: { out.yield(.level($0)) })

            var arbiter = LanguageArbiter(candidates: candidates.map(\.language))
            var chosen: VoiceLanguage? = candidates.count == 1 ? candidates[0].language : nil
            if let chosen { out.yield(.language(chosen)) }
            let started = ContinuousClock.now
            for await (index, text, confidence, isFinal) in readings {
                candidates[index].assembler.apply(text, isFinal: isFinal)
                arbiter.record(LanguageReading(
                    language: candidates[index].language, text: candidates[index].assembler.text,
                    confidence: confidence, isFinal: isFinal))
                if chosen == nil, let verdict = arbiter.verdict(force: ContinuousClock.now - started > Self.decisionDeadline) {
                    chosen = verdict
                    out.yield(.language(verdict))
                }
                let shown = chosen ?? arbiter.leader
                if let candidate = candidates.first(where: { $0.language == shown }) {
                    out.yield(.partial(candidate.assembler.text))
                }
            }
            ender.cancel()
            let finalLanguage = chosen ?? arbiter.leader ?? candidates[0].language
            if chosen == nil { out.yield(.language(finalLanguage)) }
            let finalText = candidates.first { $0.language == finalLanguage }?.assembler.text ?? ""
            out.yield(.final(finalText))
            out.finish()
        } catch {
            session.out.finish(throwing: error)
        }
    }

    /// Forwards one transcriber's results as (candidate index, text, confidence, isFinal).
    private static func read(
        _ transcriber: Transcriber, index: Int, into feed: AsyncStream<(Int, String, Double?, Bool)>.Continuation
    ) async {
        do {
            switch transcriber {
            case .speech(let speech):
                for try await result in speech.results {
                    feed.yield((index, String(result.text.characters), confidence(of: result.text), result.isFinal))
                }
            case .dictation(let dictation):
                for try await result in dictation.results {
                    feed.yield((index, String(result.text.characters), nil, result.isFinal))
                }
            }
        } catch {
            // The session ends when the stream does; a failed transcriber just stops reporting.
        }
    }

    private static func confidence(of text: AttributedString) -> Double? {
        let values = text.runs.compactMap { $0[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
