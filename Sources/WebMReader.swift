@preconcurrency import AVFoundation

/// Reads the Opus audio of a WebM file. Browsers and many web meeting tools
/// record WebM; macOS decodes Opus but does not open the container, so the
/// packets are pulled out of it here. The file is memory-mapped and read
/// front to back, which also works for recordings without a length or index.
final class WebMReader: AudioSource {
    /// WebM and Matroska start with the EBML header element.
    static func canRead(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x1A, 0x45, 0xDF, 0xA3])
    }

    private enum ID {
        static let segment: UInt32 = 0x1853_8067, tracks: UInt32 = 0x1654_AE6B, cluster: UInt32 = 0x1F43_B675
        static let blockGroup: UInt32 = 0xA0, block: UInt32 = 0xA1, simpleBlock: UInt32 = 0xA3
        static let trackEntry: UInt32 = 0xAE, trackNumber: UInt32 = 0xD7, trackType: UInt32 = 0x83
        static let codecID: UInt32 = 0x86, codecPrivate: UInt32 = 0x63A2
        /// Elements whose children are read one by one; everything else is taken or skipped whole.
        static let containers: Set<UInt32> = [segment, tracks, cluster, blockGroup]
    }

    private enum Step { case packet(Data), other, end }

    private static let opusRate: Double = 48_000
    /// Ten seconds at the usual 20 ms per packet.
    private static let batch = 500

    private let data: Data
    private var cursor: EBMLCursor
    private let output: AVAudioFormat
    private var track: Int?
    private var input: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var ended = false

    var progress: Double { data.isEmpty ? 1 : Double(cursor.offset) / Double(data.count) }

    init(url: URL, sampleRate: Double) throws {
        do {
            data = try Data(contentsOf: url, options: .alwaysMapped)
        } catch {
            throw EngineError("This file could not be read.")
        }
        cursor = EBMLCursor(data: data, offset: 0, end: data.count)
        output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        // The track list comes before the audio.
        while track == nil {
            if case .end = try step() { throw Self.unsupported }
        }
    }

    func next() throws -> [Float]? {
        guard !ended else { return nil }
        var packets: [Data] = []
        while packets.count < Self.batch, !ended {
            switch try step() {
            case .packet(let packet): packets.append(packet)
            case .other: break
            case .end: ended = true
            }
        }
        return packets.isEmpty ? nil : try decode(packets)
    }

    private static var unsupported: EngineError {
        EngineError("inlaut cannot open this file format. MP3, M4A, WAV, MP4 and MOV work.")
    }

    /// Reads one element: an audio packet, or something to pass over.
    private func step() throws -> Step {
        guard let id = cursor.id(), let size = cursor.size() else { return .end }
        if ID.containers.contains(id) {
            // Audio before any Opus track was announced: Vorbis, AAC in Matroska and the like.
            if id == ID.cluster, track == nil { throw Self.unsupported }
            return .other
        }
        guard case .known(let length) = size, cursor.offset + length <= data.count else { return .end }
        let body = cursor.offset..<cursor.offset + length
        cursor.offset = body.upperBound
        switch id {
        case ID.trackEntry:
            try readTrack(body)
        case ID.simpleBlock, ID.block:
            // Track number, two bytes of time code, one of flags, then the packet.
            var header = EBMLCursor(data: data, offset: body.lowerBound, end: body.upperBound)
            guard case .known(let number)? = header.size(), number == track, header.offset + 3 < body.upperBound else { break }
            // Bits 1–2 say several frames share the block; Opus is not stored that way.
            guard data[header.offset + 2] & 0x06 == 0 else { throw Self.unsupported }
            return .packet(data.subdata(in: header.offset + 3..<body.upperBound))
        default:
            break
        }
        return .other
    }

    private func readTrack(_ body: Range<Int>) throws {
        var entry = EBMLCursor(data: data, offset: body.lowerBound, end: body.upperBound)
        var number = 0, type = 0, codec = "", head = Data()
        while let id = entry.id(), case .known(let length)? = entry.size(), entry.offset + length <= body.upperBound {
            let value = data.subdata(in: entry.offset..<entry.offset + length)
            entry.offset += length
            switch id {
            case ID.trackNumber: number = value.reduce(0) { $0 << 8 | Int($1) }
            case ID.trackType: type = value.reduce(0) { $0 << 8 | Int($1) }
            case ID.codecID: codec = String(decoding: value, as: UTF8.self)
            case ID.codecPrivate: head = value
            default: break
            }
        }
        // Type 2 is audio. The codec's "OpusHead" carries the channel count in byte 9.
        guard track == nil, type == 2, codec == "A_OPUS", head.count > 9 else { return }
        // Zero frames per packet: every packet states its own length, since
        // Opus packets hold anything from 2.5 to 120 ms.
        var description = AudioStreamBasicDescription(
            mSampleRate: Self.opusRate, mFormatID: kAudioFormatOpus, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 0, mBytesPerFrame: 0, mChannelsPerFrame: UInt32(head[head.startIndex + 9]),
            mBitsPerChannel: 0, mReserved: 0)
        guard let input = AVAudioFormat(streamDescription: &description),
              let converter = AVAudioConverter(from: input, to: output) else { throw Self.unsupported }
        // Mix all channels; the default keeps only the first.
        converter.downmix = true
        self.input = input
        self.converter = converter
        track = number
    }

    private func decode(_ packets: [Data]) throws -> [Float] {
        guard let input, let converter else { throw Self.unsupported }
        let buffer = AVAudioCompressedBuffer(format: input, packetCapacity: AVAudioPacketCount(packets.count),
                                             maximumPacketSize: packets.reduce(1) { max($0, $1.count) })
        guard let descriptions = buffer.packetDescriptions else { throw Self.unsupported }
        var position = 0
        for (index, packet) in packets.enumerated() {
            packet.withUnsafeBytes { buffer.data.advanced(by: position).copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            descriptions[index] = AudioStreamPacketDescription(mStartOffset: Int64(position),
                                                               mVariableFramesInPacket: UInt32(Self.frames(in: packet)),
                                                               mDataByteSize: UInt32(packet.count))
            position += packet.count
        }
        buffer.byteLength = UInt32(position)
        buffer.packetCount = AVAudioPacketCount(packets.count)

        var samples: [Float] = []
        var handedOver = false
        while true {
            guard let decoded = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(output.sampleRate) * 5) else {
                throw Self.unsupported
            }
            var failure: NSError?
            let status = converter.convert(to: decoded, error: &failure) { _, state in
                if handedOver {
                    state.pointee = .noDataNow
                    return nil
                }
                handedOver = true
                state.pointee = .haveData
                return buffer
            }
            if status == .error || failure != nil { throw EngineError("This file could not be read.") }
            if let channel = decoded.floatChannelData?[0] {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(decoded.frameLength)))
            }
            if status != .haveData || decoded.frameLength == 0 { return samples }
        }
    }

    /// The length of an Opus packet in frames at 48 kHz, from its first byte
    /// (RFC 6716, section 3.1): the configuration gives the frame size, the
    /// low two bits how many frames the packet holds.
    static func frames(in packet: Data) -> Int {
        guard let first = packet.first else { return 0 }
        let configuration = Int(first >> 3)
        let size: Int
        if configuration < 12 {
            size = [480, 960, 1920, 2880][configuration % 4]
        } else if configuration < 16 {
            size = [480, 960][configuration % 2]
        } else {
            size = [120, 240, 480, 960][configuration % 4]
        }
        switch first & 0x03 {
        case 0: return size
        case 1, 2: return size * 2
        default: return packet.count > 1 ? size * Int(packet[packet.startIndex + 1] & 0x3F) : 0
        }
    }
}

/// Walks EBML, the container format of WebM and Matroska: every element is
/// an ID, a size and a body, with ID and size as variable-length integers
/// whose leading zero bits give their length.
struct EBMLCursor {
    enum Size: Equatable {
        case known(Int)
        /// A live recording does not know how long a segment or cluster gets.
        case unknown
    }

    let data: Data
    var offset: Int
    let end: Int

    /// The ID keeps its length marker, as the specification writes them.
    mutating func id() -> UInt32? {
        guard offset < end else { return nil }
        let length = data[offset].leadingZeroBitCount + 1
        guard length <= 4, offset + length <= end else { return nil }
        let value = data[offset..<offset + length].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        offset += length
        return value
    }

    mutating func size() -> Size? {
        guard offset < end else { return nil }
        let length = data[offset].leadingZeroBitCount + 1
        guard length <= 8, offset + length <= end else { return nil }
        let marker = UInt64(1) << UInt64(7 * length)
        let value = data[offset..<offset + length].reduce(UInt64(0)) { $0 << 8 | UInt64($1) } & (marker - 1)
        offset += length
        // All value bits set means "unknown".
        return value == marker - 1 ? .unknown : .known(Int(clamping: value))
    }
}
