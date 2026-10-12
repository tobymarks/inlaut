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

    func testUnknownFormatIsRejectedWithItsOwnMessage() async throws {
        let url = directory.appendingPathComponent("meeting.webm")
        try Data("no audio".utf8).write(to: url)
        do {
            _ = try await AudioFileReader(url: url, sampleRate: 16000)
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("MP3"), error.localizedDescription)
        }
    }

    /// Three seconds of a tone in the right channel only, written by ffmpeg
    /// the way a browser records: no length, no index.
    private var webm: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/right-channel-live.webm")
    }

    func testWebMIsDecodedAndItsChannelsAreMixed() throws {
        XCTAssertTrue(WebMReader.canRead(webm))
        let reader = try WebMReader(url: webm, sampleRate: 16000)
        var samples: [Float] = []
        while let next = try reader.next() { samples += next }
        XCTAssertEqual(Double(samples.count) / 16000, 3, accuracy: 0.1)
        // The tone peaks at 0.06 in the right channel: 0.03 once mixed,
        // 0.006 if only the left channel were kept.
        XCTAssertGreaterThan(samples.reduce(0) { max($0, abs($1)) }, 0.02)
        XCTAssertEqual(reader.progress, 1, accuracy: 0.01)
    }

    @MainActor
    func testWebMRunsThroughTheSamePipeline() async throws {
        final class Collected { var parts: [TranscriptPart] = [] }
        let collected = Collected()
        try await FileTranscription.run(webm) { CountingSession() } report: { part, _ in
            if let part { collected.parts.append(part) }
        }
        XCTAssertEqual(collected.parts.count, 1)
    }

    func testOtherFilesAreNotTakenForWebM() throws {
        XCTAssertFalse(WebMReader.canRead(try write(tone(seconds: 1))))
    }

    func testOpusPacketLengths() {
        XCTAssertEqual(WebMReader.frames(in: Data([0x08])), 960)          // SILK, 20 ms
        XCTAssertEqual(WebMReader.frames(in: Data([0x18])), 2880)         // SILK, 60 ms
        XCTAssertEqual(WebMReader.frames(in: Data([0x80])), 120)          // CELT, 2.5 ms
        XCTAssertEqual(WebMReader.frames(in: Data([0xF9])), 1920)         // two frames of 20 ms
        XCTAssertEqual(WebMReader.frames(in: Data([0xFB, 0x03])), 2880)   // three frames of 20 ms
        XCTAssertEqual(WebMReader.frames(in: Data()), 0)
    }

    func testEBMLSizes() {
        func size(_ bytes: [UInt8]) -> EBMLCursor.Size? {
            var cursor = EBMLCursor(data: Data(bytes), offset: 0, end: bytes.count)
            return cursor.size()
        }
        XCTAssertEqual(size([0x81]), .known(1))
        XCTAssertEqual(size([0x40, 0x02]), .known(2))
        XCTAssertEqual(size([0xFF]), .unknown)
        XCTAssertEqual(size([0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]), .unknown)
        XCTAssertNil(size([0x40]))
    }

    func testClock() {
        XCTAssertEqual(TranscriptPart(start: 0, text: "").clock, "0:00")
        XCTAssertEqual(TranscriptPart(start: 65.9, text: "").clock, "1:05")
        XCTAssertEqual(TranscriptPart(start: 3725, text: "").clock, "1:02:05")
    }
}
