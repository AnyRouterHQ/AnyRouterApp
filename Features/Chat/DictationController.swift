import Observation
import SwiftUI

/// Dictation into the composer: starts a speech engine, writes the live transcript into the field, and stops on a tap,
/// on silence, when the reader types, or when the app leaves the screen. One microphone, so one controller for the app.
@MainActor @Observable
final class DictationController {
    private(set) var phase: DictationPhase = .idle
    /// Microphone level, 0 to 1, smoothed for the meter.
    private(set) var level: Float = 0
    /// The language the engine settled on.
    private(set) var language: VoiceLanguage?
    private(set) var errorMessage: String?
    /// True while the sheet that explains on-device processing is up, before the system asks for the microphone.
    var showsExplanation = false

    var isActive: Bool { phase != .idle }

    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let needsExplanation: @MainActor () -> Bool
    @ObservationIgnored private let requestPermissions: @MainActor () async throws -> Void
    @ObservationIgnored private var engine: (any SpeechToText)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var text: Binding<String>?
    @ObservationIgnored private var hub: VoiceHub?
    @ObservationIgnored private var lastWritten: String?
    @ObservationIgnored private var silence = SilenceDetector()
    /// Bumped by every start and stop, so the end of an old session cannot reset a new one that reuses the same engine.
    @ObservationIgnored private var generation = 0

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        needsExplanation: @escaping @MainActor () -> Bool = {
            DictationRules.needsExplanation(microphone: VoicePermissions.microphone, speechRecognition: VoicePermissions.speechRecognition)
        },
        requestPermissions: @escaping @MainActor () async throws -> Void = { try await VoicePermissions.request() }
    ) {
        self.now = now
        self.needsExplanation = needsExplanation
        self.requestPermissions = requestPermissions
    }

    // MARK: Commands

    /// The tap on the mic button: start, or stop and keep the words.
    func toggle(text: Binding<String>, hub: VoiceHub) {
        switch phase {
        case .idle: begin(text: text, hub: hub)
        case .preparing, .listening: finish()
        case .finishing: break
        }
    }

    func begin(text: Binding<String>, hub: VoiceHub) {
        errorMessage = nil
        self.text = text
        self.hub = hub
        if needsExplanation() {
            showsExplanation = true
        } else {
            launch()
        }
    }

    func confirmExplanation() {
        showsExplanation = false
        launch()
    }

    func declineExplanation() {
        showsExplanation = false
        text = nil
        hub = nil
    }

    /// Stops listening and keeps the words, once the engine has finished the phrase in flight.
    func finish() {
        guard phase == .preparing || phase == .listening, let engine else { return }
        phase = .finishing
        Task { await engine.finish() }
    }

    /// Stops now. The text already in the field stays.
    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        engine?.cancel()
        reset()
    }

    /// The badge: nil detects the language. Listening restarts in the new language and keeps the words so far.
    func choose(language: VoiceLanguage?, hub: VoiceHub) {
        hub.settings.forcedLanguage = language
        guard isActive, let text else { return }
        cancel()
        begin(text: text, hub: hub)
    }

    func dismissError() { errorMessage = nil }

    // MARK: Session

    private func launch() {
        guard let hub, let text else { return }
        generation += 1
        let session = generation
        phase = .preparing
        level = 0
        language = nil
        silence = SilenceDetector()
        lastWritten = nil
        let base = text.wrappedValue
        let forced = hub.settings.forcedLanguage
        let (engine, _) = hub.speechToText(for: forced)
        self.engine = engine
        let request = SpeechRequest(
            language: forced,
            candidates: VoiceRouting.candidates(lastUsed: hub.settings.lastLanguage, deviceLanguages: Locale.preferredLanguages))
        task = Task { await run(engine, request, base: base, session: session) }
    }

    private func run(_ engine: any SpeechToText, _ request: SpeechRequest, base: String, session: Int) async {
        do {
            try await requestPermissions()
            guard session == generation else { return }
            for try await event in engine.start(request) {
                guard session == generation else { return }
                handle(event, base: base)
            }
        } catch {
            if session == generation { errorMessage = error.localizedDescription }
        }
        if session == generation { reset() }
    }

    private func handle(_ event: TranscriptEvent, base: String) {
        switch event {
        case .preparing:
            break
        case .language(let detected):
            language = detected
            hub?.settings.lastLanguage = detected
        case .level(let value):
            if phase == .preparing { phase = .listening }
            level = max(value, level * 0.6)
            if silence.observe(level: value, at: now()) { finish() }
        case .partial(let transcript):
            if phase == .preparing { phase = .listening }
            write(transcript, base: base)
        case .final(let transcript):
            write(transcript, base: base)
        }
    }

    /// Writes the transcript after `base`. If the reader changed the field meanwhile (typed, or sent), listening stops
    /// and their text stays.
    private func write(_ transcript: String, base: String) {
        guard let text else { return }
        if let lastWritten, text.wrappedValue != lastWritten {
            cancel()
            return
        }
        let merged = DictationRules.merge(base: base, transcript: transcript)
        lastWritten = merged
        text.wrappedValue = merged
    }

    private func reset() {
        phase = .idle
        level = 0
        engine = nil
        task = nil
        text = nil
        hub = nil
        lastWritten = nil
    }
}
