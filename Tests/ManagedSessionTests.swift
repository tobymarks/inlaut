@preconcurrency import AVFoundation
import Synchronization
import XCTest

private final class FakeSession: TranscriptionSession, Sendable {
    let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let cancellationCount = Mutex(0)
    let fails: Bool
    let onCancel: @Sendable () -> Void
    init(fails: Bool = false, onCancel: @escaping @Sendable () -> Void = {}) {
        self.fails = fails
        self.onCancel = onCancel
    }
    func append(_ buffer: AVAudioPCMBuffer) { }
    func finish() async throws -> String {
        if fails { throw EngineError("Simulated decode failure") }
        return "Diktat"
    }
    func cancel() async {
        cancellationCount.withLock { $0 += 1 }
        onCancel()
    }
}

@MainActor
private final class FakeEngine: TranscriptionEngine {
    let name = "Test"
    let session: FakeSession
    init(_ session: FakeSession) { self.session = session }
    func prepare() async throws { }
    func begin() throws -> TranscriptionSession { session }
}

final class ManagedSessionTests: XCTestCase {
    func testFailedCaptureStartCancelsSession() async throws {
        let cancelled = expectation(description: "Session is cancelled when microphone start fails")
        let raw = FakeSession(onCancel: { cancelled.fulfill() })
        try await MainActor.run {
            XCTAssertThrowsError(try ManagedSession.start(engine: FakeEngine(raw)) { _ in
                throw EngineError("Simulated microphone failure")
            })
        }
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertEqual(raw.cancellationCount.withLock { $0 }, 1)
    }

    func testFailedFinishCleansUpOnlyOnce() async {
        let raw = FakeSession(fails: true)
        let session = ManagedSession(raw)
        do {
            _ = try await session.finish()
            XCTFail("Expected decode error")
        } catch { }
        await session.cancel()
        XCTAssertEqual(raw.cancellationCount.withLock { $0 }, 1)
    }

    func testCancelledSessionCannotReturnText() async {
        let raw = FakeSession()
        let session = ManagedSession(raw)
        await session.cancel()
        await session.cancel()
        do {
            _ = try await session.finish()
            XCTFail("Cancelled dictation must not be pasted")
        } catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(raw.cancellationCount.withLock { $0 }, 1)
    }
}
