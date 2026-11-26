import AVFoundation

/// Taps the microphone and hands buffers in the analyzer's format to a callback. Runs on the audio thread, so it holds no UI state.
final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var running = false

    /// Converts one buffer to the target format. A class so the tap closure can hold it.
    private final class Converter: @unchecked Sendable {
        let converter: AVAudioConverter
        let target: AVAudioFormat
        let ratio: Double

        init(from source: AVAudioFormat, to target: AVAudioFormat) throws {
            guard let converter = AVAudioConverter(from: source, to: target) else {
                throw VoiceError.audioFailed("This microphone format is not supported.")
            }
            self.converter = converter
            self.target = target
            ratio = target.sampleRate / source.sampleRate
        }

        func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
            var supplied = false
            var failure: NSError?
            _ = converter.convert(to: output, error: &failure) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            return failure == nil && output.frameLength > 0 ? output : nil
        }
    }

    func start(
        target: AVAudioFormat,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws {
        let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        let converter = try Converter(from: source, to: target)
        input.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            onLevel(Self.level(of: buffer))
            if let converted = converter.convert(buffer) { onBuffer(converted) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw VoiceError.audioFailed("The microphone could not start: \(error.localizedDescription)")
        }
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Loudness on a 0 to 1 scale: RMS in decibels, with 50 dB of range below full scale.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        return min(1, max(0, (20 * log10(max(rms, 1e-7)) + 50) / 50))
    }
}
