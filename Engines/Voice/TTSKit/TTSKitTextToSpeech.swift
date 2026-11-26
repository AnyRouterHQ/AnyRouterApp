import Foundation

/// Spoken replies with a downloaded neural voice (Qwen3-TTS through TTSKit). Nothing loads until the first sentence; the
/// model (hundreds of MB of Core ML) stays loaded while replies keep coming and is dropped after an idle spell.
/// Sentences play one at a time: a new `speak` stops the one before it and waits for it to let go of the audio output.
/// `stop` cancels the sentence in flight. Cancelling while the model is still loading plays nothing once it is loaded;
/// cancelling during the last, already generated, bit of audio lets that bit finish (TTSKit cannot cut its drain short).
@MainActor
final class TTSKitTextToSpeech: TextToSpeech {
    let id: String

    private let model: VoiceModel
    private let loader: TTSBackendLoader
    private let activateAudio: @MainActor () throws -> Void
    private let idleTimeout: Duration
    private var loading: Task<any TTSBackend, Error>?
    private var unloading: Task<Void, Never>?
    private var playing: Task<Void, Error>?
    private var idleTask: Task<Void, Never>?

    init(
        model: VoiceModel, loader: @escaping TTSBackendLoader,
        activateAudio: @escaping @MainActor () throws -> Void = { try VoiceAudioSession.activatePlayback() },
        idleTimeout: Duration = .seconds(60)
    ) {
        id = model.id
        self.model = model
        self.loader = loader
        self.activateAudio = activateAudio
        self.idleTimeout = idleTimeout
    }

    func supports(_ language: VoiceLanguage) async -> Bool {
        model.supports(language) && TTSKitLanguage(language) != nil
    }

    func speak(_ text: String, language: VoiceLanguage) async throws {
        guard model.supports(language), let target = TTSKitLanguage(language) else {
            throw VoiceError.languageUnavailable(language)
        }
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        idleTask?.cancel()
        idleTask = nil
        let previous = playing
        previous?.cancel()
        do {
            try activateAudio()
        } catch {
            throw TTSFailure.map(error)
        }
        let load = backendLoad()
        let job = Task.detached { () async throws -> Void in
            _ = await previous?.result
            try Task.checkCancellation()
            let backend = try await load.value
            try Task.checkCancellation()
            try await backend.speak(sentence, language: target)
        }
        playing = job
        defer { finished(job) }
        do {
            try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
        } catch {
            // A stop is not a failure, and whatever the backend threw while it was being stopped does not matter.
            if job.isCancelled { return }
            throw TTSFailure.map(error)
        }
    }

    func stop() { playing?.cancel() }

    // MARK: Internals

    private func backendLoad() -> Task<any TTSBackend, Error> {
        if let loading { return loading }
        let pendingUnload = unloading
        let task = Task { [weak self, loader] () async throws -> any TTSBackend in
            await pendingUnload?.value
            do {
                return try await Task.detached { try await loader() }.value
            } catch {
                // A failed load is not kept: the next sentence tries again.
                self?.loading = nil
                throw error
            }
        }
        loading = task
        return task
    }

    private func finished(_ job: Task<Void, Error>) {
        guard playing == job else { return }
        playing = nil
        idleTask?.cancel()
        idleTask = Task { [weak self, idleTimeout] in
            try? await Task.sleep(for: idleTimeout)
            if !Task.isCancelled { await self?.unloadIfIdle() }
        }
    }

    private func unloadIfIdle() async {
        guard playing == nil, let load = loading else { return }
        loading = nil
        let unload = Task {
            if let backend = try? await load.value { await backend.unload() }
        }
        unloading = unload
        await unload.value
        if unloading == unload { unloading = nil }
    }
}
