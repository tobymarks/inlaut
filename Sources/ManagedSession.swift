@preconcurrency import AVFoundation
import Synchronization

/// Owns cancellation across capture-start failures, decode failures and user
/// cancellation. Engines see at most one cancel call, even when paths overlap.
final class ManagedSession: TranscriptionSession {
    private let underlying: TranscriptionSession
    private let cancelled = Atomic<Bool>(false)
    var audioFormat: AVAudioFormat { underlying.audioFormat }

    init(_ underlying: TranscriptionSession) { self.underlying = underlying }

    @MainActor
    static func start(engine: TranscriptionEngine,
                      capture: (TranscriptionSession) throws -> Void) throws -> ManagedSession {
        let session = ManagedSession(try engine.begin())
        do {
            try capture(session)
            return session
        } catch {
            Task { await session.cancel() }
            throw error
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        if !cancelled.load(ordering: .relaxed) { underlying.append(buffer) }
    }

    func finish() async throws -> String {
        do {
            try Task.checkCancellation()
            if cancelled.load(ordering: .relaxed) { throw CancellationError() }
            let text = try await underlying.finish()
            try Task.checkCancellation()
            if cancelled.load(ordering: .relaxed) { throw CancellationError() }
            return text
        } catch {
            await cancel()
            throw error
        }
    }

    func cancel() async {
        if !cancelled.exchange(true, ordering: .relaxed) { await underlying.cancel() }
    }
}
