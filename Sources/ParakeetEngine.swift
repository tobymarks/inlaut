@preconcurrency import AVFoundation
import CoreML
import InlautSpeech
import Synchronization

/// Parakeet as Core ML components on the Neural Engine, through FluidAudio.
/// A loaded model costs ~35 MB in the process (~150 MB in the system), loads
/// in ~0.2 s once macOS has compiled it for the Neural Engine, and turns a
/// 10 s clip into text in well under 0.1 s.
@MainActor
final class ParakeetEngine: TranscriptionEngine {
    let model: SpeechModel
    var name: String { model.name }
    private var recognizer: ParakeetRecognizer?
    /// A load in flight. A take can already record meanwhile; only its
    /// transcription waits for the model. The very first load after a
    /// download also compiles for the Neural Engine (~10–30 s), later ones
    /// take ~0.2 s.
    private var loading: Task<ParakeetRecognizer, Error>?

    init(model: SpeechModel) {
        self.model = model
    }

    var isLoaded: Bool { recognizer != nil }
    var isLoading: Bool { loading != nil }

    /// Starts loading right away, so `begin` can hand out a session before
    /// the model is ready.
    func startLoading() throws {
        guard recognizer == nil, loading == nil else { return }
        guard model.isInstalled else { throw EngineError("The Parakeet model has not been downloaded yet.") }
        let directory = model.directory
        loading = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try await ParakeetRecognizer(directory: directory)
        }
    }

    func prepare() async throws {
        guard recognizer == nil else { return }
        try startLoading()
        guard let task = loading else { return }
        defer { if loading == task { loading = nil } }
        let prepared = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        recognizer = prepared
    }

    func unload() {
        // An active session retains its recognizer until its take finishes.
        recognizer = nil
        loading?.cancel()
        loading = nil
    }

    func begin() throws -> TranscriptionSession {
        if let recognizer { return ParakeetSession { recognizer } }
        if let loading { return ParakeetSession { try await loading.value } }
        throw EngineError("Parakeet is not ready yet.")
    }
}

final class ParakeetSession: TranscriptionSession, @unchecked Sendable {
    let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: ParakeetRecognizer.sampleRate,
                                    channels: 1, interleaved: false)!
    private let recognizer: @Sendable () async throws -> ParakeetRecognizer
    private let samples = Mutex<[Float]>([])
    private let cancellation = CancellationFlag()

    /// `recognizer` may still be loading; `finish` waits for it.
    init(recognizer: @escaping @Sendable () async throws -> ParakeetRecognizer) {
        self.recognizer = recognizer
        samples.withLock { $0.reserveCapacity(Int(ParakeetRecognizer.sampleRate) * 30) }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let chunk = UnsafeBufferPointer(start: data, count: Int(buffer.frameLength))
        samples.withLock { if !cancellation.isCancelled { $0.append(contentsOf: chunk) } }
    }

    func finish() async throws -> String {
        let audio = samples.withLock { samples in
            let audio = samples
            samples = []
            return audio
        }
        return try await withTaskCancellationHandler {
            try cancellation.check()
            let recognizer = try await recognizer()
            try cancellation.check()
            return try await recognizer.transcribe(audio, cancellation: cancellation)
        } onCancel: {
            cancellation.cancel()
        }
    }

    func cancel() async {
        cancellation.cancel()
        samples.withLock { $0.removeAll() }
    }
}

/// Owns FluidAudio's AsrManager (an actor, so decodes are serialised).
/// Long takes are split into 15 s windows by FluidAudio itself.
final class ParakeetRecognizer: Sendable {
    static let sampleRate: Double = 16_000

    private let manager: AsrManager

    init(directory: URL) async throws {
        // Loads the compiled components from our own pinned, checksummed
        // copy; nothing is fetched from the network.
        let models = try AsrModels.loadLocal(from: directory, version: .ultra)
        try Task.checkCancellation()
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
        // The first decode after loading is noticeably slower without a warm-up.
        var state = TdtDecoderState.make()
        _ = try? await manager.transcribe([Float](repeating: 0, count: Int(Self.sampleRate)), decoderState: &state)
    }

    // Quiet speech (peak ~0.03) loses words; raised to a peak of 0.5 it decodes in full.
    private static let targetPeak: Float = 0.5
    private static let maxGain: Float = 30

    func transcribe(_ audio: [Float], cancellation: CancellationFlag) async throws -> String {
        try cancellation.check()
        var samples = audio
        // FluidAudio rejects takes under 0.3 s; trailing silence changes nothing.
        let minimum = Int(Self.sampleRate * 0.35)
        if samples.count < minimum { samples += [Float](repeating: 0, count: minimum - samples.count) }
        let peak = samples.reduce(0) { max($0, abs($1)) }
        if peak > 0, peak < Self.targetPeak {
            let gain = min(Self.targetPeak / peak, Self.maxGain)
            for i in samples.indices { samples[i] *= gain }
        }
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(samples, decoderState: &state)
        try cancellation.check()
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
