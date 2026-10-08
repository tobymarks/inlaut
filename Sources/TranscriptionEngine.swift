@preconcurrency import AVFoundation

/// A speech-to-text backend. Apple's on-device recogniser is the first one;
/// a local Parakeet model can follow behind the same two protocols.
@MainActor
protocol TranscriptionEngine: AnyObject {
    var name: String { get }
    /// Download models or check availability. Throws a message for the user.
    func prepare() async throws
    /// Start a session; audio is pushed into it while the hotkey is held.
    func begin(vocabulary: [String]) throws -> TranscriptionSession
}

/// One dictation. `append` is called on the audio thread, so implementations
/// must be safe to call from there.
protocol TranscriptionSession: AnyObject, Sendable {
    /// The format `append` expects; the recorder converts to it.
    var audioFormat: AVAudioFormat { get }
    func append(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> String
    func cancel() async
}

struct EngineError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
