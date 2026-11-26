import Foundation

/// Dictation with a downloaded Whisper model. One long-lived runner task owns the loaded model (a Core ML load takes
/// seconds and holds hundreds of MB), serves one dictation at a time and unloads the model after an idle spell. Nothing
/// loads until the first `start`. Whisper reports the language it hears, so with no language asked for it detects one
/// after about a second and a half of speech and keeps it for the rest of the dictation.
@MainActor
final class WhisperKitSpeechToText: SpeechToText {
    let id: String

    private let model: VoiceModel
    private let audio: WhisperAudioHooks
    private let idleTimeout: Duration
    private let pollInterval: Duration
    private let jobs: AsyncStream<WhisperSessionRunner.Job>.Continuation
    private var session: Session?
    private var idleTask: Task<Void, Never>?

    @MainActor private final class Session {
        let signal = WhisperSessionSignal()
        let out: AsyncThrowingStream<TranscriptEvent, Error>.Continuation

        init(out: AsyncThrowingStream<TranscriptEvent, Error>.Continuation) { self.out = out }
    }

    init(
        model: VoiceModel, loader: @escaping WhisperBackendLoader, audio: WhisperAudioHooks,
        idleTimeout: Duration = .seconds(60), pollInterval: Duration = .milliseconds(100)
    ) {
        id = model.id
        self.model = model
        self.audio = audio
        self.idleTimeout = idleTimeout
        self.pollInterval = pollInterval
        let (stream, continuation) = AsyncStream<WhisperSessionRunner.Job>.makeStream()
        jobs = continuation
        Task.detached(priority: .userInitiated) { await WhisperSessionRunner.run(loader: loader, jobs: stream) }
    }

    deinit { jobs.finish() }

    func supports(_ language: VoiceLanguage) async -> Bool { model.supports(language) }

    func start(_ request: SpeechRequest) -> AsyncThrowingStream<TranscriptEvent, Error> {
        cancel()
        idleTask?.cancel()
        idleTask = nil
        let (stream, out) = AsyncThrowingStream<TranscriptEvent, Error>.makeStream()
        let session = Session(out: out)
        self.session = session
        out.onTermination = { @Sendable _ in
            Task { @MainActor [weak self] in self?.ended(session) }
        }
        jobs.yield(.listen(WhisperSessionRunner.Listen(
            request: request, signal: session.signal, out: out, audio: audio, pollInterval: pollInterval)))
        return stream
    }

    func finish() async {
        guard let session else { return }
        await session.signal.request(.finish)
        await session.signal.waitUntilDone()
    }

    func cancel() {
        guard let session else { return }
        self.session = nil
        session.out.finish()
        Task { await session.signal.request(.cancel) }
    }

    /// The stream is over, by `final`, an error, or its reader leaving.
    private func ended(_ session: Session) {
        if self.session === session { cancel() }
        idleTask?.cancel()
        idleTask = Task { [jobs, idleTimeout] in
            try? await Task.sleep(for: idleTimeout)
            if !Task.isCancelled { jobs.yield(.unload) }
        }
    }
}

/// How a dictation is told to stop, and how the caller waits for it to wind down.
actor WhisperSessionSignal {
    enum Stop: Sendable { case finish, cancel }

    private(set) var stop: Stop?
    private var isDone = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// A cancel overrides a finish, never the other way round.
    func request(_ stop: Stop) {
        if self.stop == nil || stop == .cancel { self.stop = stop }
    }

    func markDone() {
        isDone = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }

    func waitUntilDone() async {
        if isDone { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// The task that owns the backend. Plain functions with no actor of their own, so the non-Sendable backend stays in
/// one place.
enum WhisperSessionRunner {
    struct Listen: Sendable {
        var request: SpeechRequest
        var signal: WhisperSessionSignal
        var out: AsyncThrowingStream<TranscriptEvent, Error>.Continuation
        var audio: WhisperAudioHooks
        var pollInterval: Duration
    }

    enum Job: Sendable {
        case listen(Listen)
        case unload
    }

    static func run(loader: WhisperBackendLoader, jobs: AsyncStream<Job>) async {
        var backend: (any WhisperBackend)?
        for await job in jobs {
            switch job {
            case .unload:
                await backend?.unload()
                backend = nil
            case .listen(let listen):
                await serve(listen, loader: loader, backend: &backend)
            }
        }
        await backend?.unload()
    }

    private static func serve(
        _ job: Listen, loader: WhisperBackendLoader, backend: inout (any WhisperBackend)?
    ) async {
        let out = job.out
        var audioActive = false
        do {
            if await stoppedBeforeStart(job) { return }
            out.yield(.preparing(nil))
            let live: any WhisperBackend
            if let loaded = backend {
                live = loaded
            } else {
                live = try await loader()
                backend = live
            }
            // Cancelled, or stopped, while the model was loading.
            if await stoppedBeforeStart(job) { return }
            try await job.audio.activate()
            audioActive = true
            try live.startRecording()
            try await listenLoop(job, live)
        } catch {
            backend?.stopRecording()
            out.finish(throwing: WhisperFailure.map(error))
        }
        if audioActive { await job.audio.deactivate() }
        await job.signal.markDone()
    }

    /// A stop that came before the microphone started: nothing was heard, so a finish reports an empty transcript.
    private static func stoppedBeforeStart(_ job: Listen) async -> Bool {
        guard let stop = await job.signal.stop else { return false }
        if stop == .finish { job.out.yield(.final("")) }
        job.out.finish()
        await job.signal.markDone()
        return true
    }

    /// Records and transcribes until told to stop. A cancel ends the stream with no `final`.
    private static func listenLoop(_ job: Listen, _ backend: any WhisperBackend) async throws {
        let out = job.out
        var trigger = WhisperLanguageTrigger(forced: job.request.language)
        var transcript = WhisperTranscript()
        var transcribed = 0
        if let forced = trigger.language { out.yield(.language(forced)) }

        func detect(isEnding: Bool) async throws {
            let energy = backend.energy
            let voiced = WhisperVoice.voicedSeconds(energy: energy, sampleCount: backend.sampleCount)
            guard trigger.shouldDetect(voicedSeconds: voiced, isEnding: isEnding) else { return }
            let code = try await backend.detectLanguage(in: backend.samples())
            trigger.settle(WhisperLanguages.voiceLanguage(fromWhisper: code))
            if let language = trigger.language { out.yield(.language(language)) }
        }

        while true {
            let stop = await job.signal.stop
            if stop == .cancel {
                backend.stopRecording()
                out.finish()
                return
            }
            if stop == .finish { break }
            let energy = backend.energy
            let count = backend.sampleCount
            if let level = energy.last { out.yield(.level(min(1, max(0, level)))) }
            try await detect(isEnding: false)
            if let language = trigger.language,
               WhisperPacing.shouldTranscribe(energy: energy, sampleCount: count, transcribedSamples: transcribed) {
                let samples = backend.samples()
                let segments = try await backend.transcribe(
                    samples, language: WhisperLanguages.whisperCode(for: language), from: transcript.confirmedEnd)
                transcribed = samples.count
                transcript.apply(segments)
                out.yield(.partial(transcript.text))
            } else {
                try? await Task.sleep(for: job.pollInterval)
            }
        }

        // Stopped: one last pass over everything, then the whole transcript.
        backend.stopRecording()
        try await detect(isEnding: true)
        let energy = backend.energy
        let heard = WhisperVoice.voicedSeconds(energy: energy, sampleCount: backend.sampleCount) > 0
        if let language = trigger.language, heard {
            let segments = try await backend.transcribe(
                backend.samples(), language: WhisperLanguages.whisperCode(for: language), from: transcript.confirmedEnd)
            transcript.apply(segments, isFinal: true)
        } else {
            transcript.finish()
        }
        out.yield(.final(transcript.text))
        out.finish()
    }
}
