@preconcurrency import AVFoundation
import Synchronization
import XCTest

private final class CountingSession: TranscriptionSession, Sendable {
    let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let frames = Mutex(0)
    func append(_ buffer: AVAudioPCMBuffer) { frames.withLock { $0 += Int(buffer.frameLength) } }
    func finish() async throws -> String { "\(frames.withLock { $0 }) frames" }
    func cancel() async { }
}

final class FileTranscriptionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// A 440 Hz tone that is silent in the given ranges (seconds).
    private func tone(seconds: Double, sampleRate: Double = 16000, quiet: [ClosedRange<Double>] = []) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { index in
            let time = Double(index) / sampleRate
            return quiet.contains { $0.contains(time) } ? 0 : Float(sin(2 * .pi * 440 * time)) * 0.3
        }
    }

    private func write(_ samples: [Float], sampleRate: Double = 16000, channels: AVAudioChannelCount = 1) throws -> URL {
        let url = directory.appendingPathComponent("\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(channels) {
            samples.withUnsafeBufferPointer { buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: samples.count) }
        }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
        return url
    }

    func testCutFallsIntoThePause() {
        var segmenter = SpeechSegmenter(sampleRate: 16000)
        let pieces = segmenter.append(tone(seconds: 80, quiet: [50...52]))
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(Double(pieces[0].count) / 16000, 50, accuracy: 0.2)
        XCTAssertEqual(Double(segmenter.finish()?.count ?? 0) / 16000, 30, accuracy: 0.2)
        XCTAssertNil(segmenter.finish())
    }

    func testShortRecordingStaysInOnePiece() {
        var segmenter = SpeechSegmenter(sampleRate: 16000)
        XCTAssertTrue(segmenter.append(tone(seconds: 20)).isEmpty)
        XCTAssertEqual(segmenter.finish()?.count, 20 * 16000)
    }

    func testReaderMixesDownAndResamples() async throws {
        let url = try write(tone(seconds: 2, sampleRate: 44100), sampleRate: 44100, channels: 2)
        let reader = try await AudioFileReader(url: url, sampleRate: 16000)
        var samples: [Float] = []
        while let next = try reader.next() { samples += next }
        XCTAssertEqual(reader.duration, 2, accuracy: 0.01)
        XCTAssertEqual(Double(samples.count), 32000, accuracy: 200)
        XCTAssertGreaterThan(samples.reduce(0) { max($0, abs($1)) }, 0.2)
    }

    @MainActor
    func testReportsPiecesWithTheirStartAndSkipsSilence() async throws {
        // Sound, a pause to cut in, sound, then more than a piece of silence.
        let url = try write(tone(seconds: 180, quiet: [50...52, 100...180]))
        final class Collected { var parts: [TranscriptPart] = []; var fractions: [Double] = [] }
        let collected = Collected()
        try await FileTranscription.run(url) { CountingSession() } report: { part, fraction in
            if let part { collected.parts.append(part) }
            collected.fractions.append(fraction)
        }
        XCTAssertEqual(collected.parts.count, 2)
        XCTAssertEqual(collected.parts.first?.start, 0)
        XCTAssertEqual(collected.parts.last?.start ?? 0, 50, accuracy: 0.2)
        XCTAssertGreaterThan(collected.fractions.count, 2)
        XCTAssertEqual(collected.fractions.last ?? 0, 1, accuracy: 0.01)
    }

    func testFileWithoutAudioIsRejected() async throws {
        let url = directory.appendingPathComponent("notes.wav")
        try Data("no audio".utf8).write(to: url)
        do {
            _ = try await AudioFileReader(url: url, sampleRate: 16000)
            XCTFail("expected an error")
        } catch { }
    }

    func testClock() {
        XCTAssertEqual(TranscriptPart(start: 0, text: "").clock, "0:00")
        XCTAssertEqual(TranscriptPart(start: 65.9, text: "").clock, "1:05")
        XCTAssertEqual(TranscriptPart(start: 3725, text: "").clock, "1:02:05")
    }
}
