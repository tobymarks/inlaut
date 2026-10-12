@preconcurrency import AVFoundation
import os

/// One piece of a transcribed recording and where it starts in the file.
struct TranscriptPart: Equatable, Sendable {
    let start: TimeInterval
    let text: String

    /// The start as 1:05 or 1:02:05.
    var clock: String {
        let total = Int(start)
        let (hours, minutes, seconds) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// Turns a recording (audio or video file) into text with the same engine
/// that dictates. The file is decoded and transcribed piece by piece, so an
/// hour of audio never sits in memory at once, progress is visible and a
/// dictation in between only waits for the piece in flight.
enum FileTranscription {
    /// A piece that never gets louder than this (about −54 dBFS) is a pause.
    /// The recogniser would raise it to full level and decode the noise.
    static let silence: Float = 0.002

    /// `begin` hands out one session per piece. `report` gets each piece's
    /// text (nil when nothing was said) and the fraction of the file done.
    static func run(_ url: URL,
                    begin: @escaping @MainActor @Sendable () throws -> TranscriptionSession,
                    report: @escaping @MainActor @Sendable (TranscriptPart?, Double) -> Void) async throws {
        var session = try await begin()
        do {
            let rate = session.audioFormat.sampleRate
            let reader = try await AudioFileReader(url: url, sampleRate: rate)
            var segmenter = SpeechSegmenter(sampleRate: rate)
            var position = 0
            var pieces: [[Float]] = []
            var ended = false
            while !ended {
                if let samples = try reader.next() {
                    pieces = segmenter.append(samples)
                } else {
                    pieces = segmenter.finish().map { [$0] } ?? []
                    ended = true
                }
                for piece in pieces {
                    try Task.checkCancellation()
                    let start = Double(position) / rate
                    position += piece.count
                    var part: TranscriptPart?
                    if piece.contains(where: { abs($0) >= silence }) {
                        session.append(try buffer(piece, format: session.audioFormat))
                        let text = try await session.finish()
                        session = try await begin()
                        if !text.isEmpty { part = TranscriptPart(start: start, text: text) }
                    }
                    let done = reader.duration > 0 ? min(1, Double(position) / rate / reader.duration) : 0
                    await report(part, done)
                }
            }
            // The spare session of the last round.
            await session.cancel()
        } catch {
            await session.cancel()
            throw error
        }
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                                 channels: 1, interleaved: false)!
        let frames = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else {
            throw EngineError("This file could not be read.")
        }
        buffer.frameLength = frames
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        if format == mono { return buffer }
        // Apple's recogniser asks for its own sample format at the same rate.
        guard let converter = AVAudioConverter(from: mono, to: format),
              let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw EngineError("This file could not be read.")
        }
        try converter.convert(to: converted, from: buffer)
        return converted
    }
}

/// Decodes the audio tracks of a file to mono samples at the engine's rate.
/// AVAssetReader also opens video containers, which AVAudioFile does not.
final class AudioFileReader {
    let duration: TimeInterval
    private static let log = Logger(subsystem: "de.tobymarks.inlaut", category: "file")
    private let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput

    init(url: URL, sampleRate: Double) async throws {
        let asset = AVURLAsset(url: url)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
            duration = try await asset.load(.duration).seconds
        } catch {
            // Domain and code only; the description can carry the file name.
            let failure = error as NSError
            Self.log.error("open failed: \(failure.domain, privacy: .public) \(failure.code)")
            // WebM, Matroska and Windows Media, for example.
            if (error as? AVError)?.code == .fileFormatNotRecognized {
                throw EngineError("inlaut cannot open this file format. MP3, M4A, WAV, MP4 and MOV work.")
            }
            throw EngineError("This file could not be read.")
        }
        guard !tracks.isEmpty else { throw EngineError("This file contains no audio.") }
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? EngineError("This file could not be read.") }
    }

    /// The next stretch of samples, or nil at the end of the file.
    func next() throws -> [Float]? {
        guard let sample = output.copyNextSampleBuffer() else {
            if reader.status == .failed { throw reader.error ?? EngineError("This file could not be read.") }
            return nil
        }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        let status = samples.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { throw EngineError("This file could not be read.") }
        return samples
    }
}

/// Cuts a long recording into pieces of about a minute, each at the quietest
/// moment nearby, so a cut falls into a pause and not into a word.
struct SpeechSegmenter {
    static let shortest: TimeInterval = 45
    static let longest: TimeInterval = 75

    private let sampleRate: Double
    private var pending: [Float] = []

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    /// Returns the pieces that are complete now.
    mutating func append(_ samples: [Float]) -> [[Float]] {
        pending += samples
        var pieces: [[Float]] = []
        let longest = Int(Self.longest * sampleRate)
        while pending.count >= longest {
            let cut = Self.quietestCut(in: pending, from: Int(Self.shortest * sampleRate), to: longest,
                                       frame: Int(sampleRate / 10))
            pieces.append(Array(pending[..<cut]))
            pending.removeFirst(cut)
        }
        return pieces
    }

    /// What is left at the end of the file.
    mutating func finish() -> [Float]? {
        defer { pending = [] }
        return pending.isEmpty ? nil : pending
    }

    /// The middle of the frame with the least energy between `from` and `to`.
    static func quietestCut(in samples: [Float], from: Int, to: Int, frame: Int) -> Int {
        var best = to
        var lowest = Float.infinity
        var start = from
        while start + frame <= to {
            var energy: Float = 0
            for index in start..<start + frame { energy += samples[index] * samples[index] }
            if energy < lowest {
                lowest = energy
                best = start + frame / 2
            }
            start += frame
        }
        return best
    }
}
