@preconcurrency import AVFoundation
import SherpaOnnx
import Synchronization

/// Parakeet through sherpa-onnx on the CPU. The model is loaded once and
/// kept in memory, so a dictation starts instantly and a 10 s clip is text
/// in about a third of a second.
@MainActor
final class ParakeetEngine: TranscriptionEngine {
    let model: SpeechModel
    var name: String { model.name }
    private var recognizer: SherpaRecognizer?

    init(model: SpeechModel) {
        self.model = model
    }

    var isLoaded: Bool { recognizer != nil }

    func prepare() async throws {
        guard recognizer == nil else { return }
        guard model.isInstalled else { throw EngineError("The Parakeet model has not been downloaded yet.") }
        let threads = min(4, ProcessInfo.processInfo.activeProcessorCount)
        let directory = model.directory
        let loading = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try SherpaRecognizer(directory: directory, threads: threads)
        }
        let prepared = try await withTaskCancellationHandler {
            try await loading.value
        } onCancel: {
            loading.cancel()
        }
        try Task.checkCancellation()
        recognizer = prepared
    }

    func unload() {
        // An active session retains its recognizer until its take finishes.
        recognizer = nil
    }

    func begin() throws -> TranscriptionSession {
        guard let recognizer else { throw EngineError("Parakeet is not ready yet.") }
        return ParakeetSession(recognizer: recognizer)
    }
}

final class ParakeetSession: TranscriptionSession, @unchecked Sendable {
    let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: SherpaRecognizer.sampleRate,
                                    channels: 1, interleaved: false)!
    private let recognizer: SherpaRecognizer
    private let samples = Mutex<[Float]>([])
    private let cancellation = CancellationFlag()

    init(recognizer: SherpaRecognizer) {
        self.recognizer = recognizer
        samples.withLock { $0.reserveCapacity(Int(SherpaRecognizer.sampleRate) * 30) }
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

/// Owns the sherpa-onnx recognizer. It is not thread-safe, so every decode
/// runs on one serial queue.
final class SherpaRecognizer: @unchecked Sendable {
    static let sampleRate: Double = 16_000

    private let handle: OpaquePointer
    private let queue = DispatchQueue(label: "de.tobymarks.inlaut.parakeet", qos: .userInitiated)

    init(directory: URL, threads: Int) throws {
        var config = SherpaOnnxOfflineRecognizerConfig()
        config.feat_config.sample_rate = Int32(Self.sampleRate)
        config.feat_config.feature_dim = 80
        config.model_config.num_threads = Int32(threads)

        // The C strings only need to live until the recognizer is created.
        let values: [String] = [
            directory.appending(path: "encoder.int8.onnx").path,
            directory.appending(path: "decoder.int8.onnx").path,
            directory.appending(path: "joiner.int8.onnx").path,
            directory.appending(path: "tokens.txt").path,
            "cpu", "nemo_transducer", "greedy_search",
        ]
        // Explicit C-string conversion also compiles with the Xcode 26 SDK.
        let strings: [UnsafeMutablePointer<CChar>?] = values.map { value in
            value.withCString { strdup($0) }
        }
        defer { strings.forEach { free($0) } }
        config.model_config.transducer.encoder = UnsafePointer(strings[0])
        config.model_config.transducer.decoder = UnsafePointer(strings[1])
        config.model_config.transducer.joiner = UnsafePointer(strings[2])
        config.model_config.tokens = UnsafePointer(strings[3])
        config.model_config.provider = UnsafePointer(strings[4])
        config.model_config.model_type = UnsafePointer(strings[5])
        config.decoding_method = UnsafePointer(strings[6])

        guard let handle = SherpaOnnxCreateOfflineRecognizer(&config) else {
            throw EngineError("The Parakeet model could not be loaded.")
        }
        self.handle = handle
        // The first decode is about twice as slow without a warm-up.
        let silence = [Float](repeating: 0, count: Int(Self.sampleRate))
        _ = decode(silence[...])
        _ = decode(silence[...])
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(handle)
    }

    func transcribe(_ audio: [Float], cancellation: CancellationFlag) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.process(audio, cancellation: cancellation) })
            }
        }
    }

    // MARK: - Decoding (on `queue` only)

    // The encoder fails beyond ~400 s and its memory grows quadratically
    // before that, so long dictations are decoded in pieces cut at pauses.
    private static let maxPiece = 90.0
    private static let retryPiece = 20.0
    private static let targetPeak: Float = 0.5
    private static let maxGain: Float = 30

    private func process(_ audio: [Float], cancellation: CancellationFlag) throws -> String {
        try cancellation.check()
        var parts: [String] = []
        for piece in Self.split(audio[...], maxSeconds: Self.maxPiece) {
            try cancellation.check()
            var text = decode(piece)
            // Now and then a long piece that clearly holds speech comes back
            // empty; shorter pieces of the same audio decode fine.
            if text.isEmpty, Double(piece.count) > Self.retryPiece * Self.sampleRate {
                text = try Self.split(piece, maxSeconds: Self.retryPiece).map { part in
                    try cancellation.check()
                    return decode(part)
                }
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
            if !text.isEmpty { parts.append(text) }
        }
        try cancellation.check()
        return parts.joined(separator: " ")
    }

    private func decode(_ piece: ArraySlice<Float>) -> String {
        guard !piece.isEmpty else { return "" }
        // Quiet speech (peak ~0.03) comes back empty; the same audio raised
        // to a peak of 0.5 decodes in full.
        var samples = Array(piece)
        let peak = samples.reduce(0) { max($0, abs($1)) }
        if peak > 0, peak < Self.targetPeak {
            let gain = min(Self.targetPeak / peak, Self.maxGain)
            for i in samples.indices { samples[i] *= gain }
        }
        guard let stream = SherpaOnnxCreateOfflineStream(handle) else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        samples.withUnsafeBufferPointer {
            SherpaOnnxAcceptWaveformOffline(stream, Int32(Self.sampleRate), $0.baseAddress, Int32($0.count))
        }
        SherpaOnnxDecodeOfflineStream(handle, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        guard let text = result.pointee.text else { return "" }
        return String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Pieces of at most `maxSeconds`, each cut at the quietest spot in its last part.
    private static func split(_ audio: ArraySlice<Float>, maxSeconds: Double) -> [ArraySlice<Float>] {
        let maxN = Int(maxSeconds * sampleRate)
        let searchN = Int(min(15, maxSeconds / 2) * sampleRate)
        let windowN = Int(0.4 * sampleRate)
        var rest = audio
        var pieces: [ArraySlice<Float>] = []
        while rest.count > maxN {
            let start = rest.startIndex
            var bestCut = start + maxN
            var bestEnergy = Float.infinity
            var w = start + maxN - searchN
            while w + windowN <= start + maxN {
                var energy: Float = 0
                for i in w..<(w + windowN) { energy += rest[i] * rest[i] }
                if energy < bestEnergy { bestEnergy = energy; bestCut = w + windowN / 2 }
                w += windowN
            }
            pieces.append(rest[start..<bestCut])
            rest = rest[bestCut...]
        }
        pieces.append(rest)
        return pieces
    }
}
