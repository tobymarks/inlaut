@preconcurrency import AVFoundation

/// Microphone capture that only exists while a dictation runs: a fresh
/// AVAudioEngine per take, torn down right after, so the mic indicator goes
/// off and nothing keeps running between dictations.
@MainActor
final class Recorder {
    private var engine: AVAudioEngine?
    private var meter: Meter?
    private var startedAt = Date()

    /// Seconds recorded and the loudest sample (0…1). A peak of exactly 0
    /// means macOS handed out silence — the microphone permission is missing.
    struct Take { let seconds: TimeInterval; let peak: Float }

    func start(into session: TranscriptionSession) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw EngineError("Kein Mikrofon gefunden.")
        }
        guard let converter = AVAudioConverter(from: inFormat, to: session.audioFormat) else {
            throw EngineError("Audioformat des Mikrofons wird nicht unterstützt.")
        }
        let meter = Meter()
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat,
                         block: Self.tap(meter: meter, converter: converter, session: session))
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.meter = meter
        startedAt = Date()
    }

    /// Loudest sample of the latest buffer (0…1), for the level display.
    var level: Float { meter?.current ?? 0 }

    func stop() -> Take {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        let take = Take(seconds: Date().timeIntervalSince(startedAt), peak: meter?.peak ?? 0)
        meter = nil
        return take
    }

    /// Built outside the main actor on purpose: a closure written inside a
    /// @MainActor method inherits that isolation, and Swift 6 traps when
    /// AVAudioEngine then calls it on its realtime queue.
    nonisolated private static func tap(meter: Meter, converter: AVAudioConverter,
                                        session: TranscriptionSession) -> AVAudioNodeTapBlock {
        let format = session.audioFormat
        return { buffer, _ in
            meter.update(buffer)
            if let converted = convert(buffer, with: converter, to: format) {
                session.append(converted)
            }
        }
    }

    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }
}

/// Peak levels, written on the audio thread. A torn Float read on the main
/// thread only makes one bar of the level display a little off.
private final class Meter: @unchecked Sendable {
    private(set) var peak: Float = 0
    private(set) var current: Float = 0

    func update(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        var loudest: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            loudest = max(loudest, abs(data[i]))
        }
        current = loudest
        peak = max(peak, loudest)
    }
}
