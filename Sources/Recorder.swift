@preconcurrency import AVFoundation
import CoreAudio
import Synchronization

/// Microphone capture that only exists while a dictation runs: a fresh
/// AVAudioEngine per take, torn down right after, so the mic indicator goes
/// off and nothing keeps running between dictations.
///
/// AVAudioEngine always opens the system's input device. For any other
/// microphone an AVCaptureSession opens that device directly: pointing the
/// engine at it afterwards still woke a Bluetooth headset that was the
/// system input, which swallowed the start sound and cost ~200 ms.
@MainActor
final class Recorder {
    private var engine: AVAudioEngine?
    private var capture: AVCaptureSession?
    private var sink: CaptureSink?
    private var meter: Meter?
    private var startedAt = Date()

    /// Seconds recorded and the loudest sample (0…1). A peak of exactly 0
    /// means macOS handed out silence — the microphone permission is missing.
    struct Take { let seconds: TimeInterval; let peak: Float; let startup: Startup }

    /// How long the microphone took to deliver audio, in milliseconds from the
    /// moment capture was requested (-1 = never). Bluetooth headsets switch to
    /// their hands-free profile first and stay silent for a while.
    struct Startup {
        var engineMs = -1, firstBufferMs = -1, firstSignalMs = -1
        var bluetooth = false
    }
    private var startup = Startup()

    func start(into session: TranscriptionSession, device: InputDevice? = nil) throws {
        #if DEBUG
        // End-to-end tests: `-testAudioFile /path.wav` replaces the microphone,
        // so a synthetic key press dictates a known recording.
        if let path = UserDefaults.standard.string(forKey: "testAudioFile") {
            try feed(path, into: session)
            return
        }
        #endif
        let requested = DispatchTime.now().uptimeNanoseconds
        let meter = Meter(since: requested)
        if let device, device.id != Microphones.systemDefault()?.id {
            try startCapture(device, into: session, meter: meter)
        } else {
            try startEngine(into: session, meter: meter)
        }
        self.meter = meter
        startup = Startup(engineMs: Int((DispatchTime.now().uptimeNanoseconds - requested) / 1_000_000),
                          bluetooth: device?.isBluetooth ?? false)
        startedAt = Date()
    }

    private func startEngine(into session: TranscriptionSession, meter: Meter) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else {
            throw EngineError("No microphone found.")
        }
        guard let converter = AVAudioConverter(from: inFormat, to: session.audioFormat) else {
            throw EngineError("The microphone's audio format is not supported.")
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat,
                         block: Self.tap(meter: meter, converter: converter, session: session))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            throw error
        }
        self.engine = engine
    }

    private func startCapture(_ device: InputDevice, into session: TranscriptionSession, meter: Meter) throws {
        guard let microphone = AVCaptureDevice(uniqueID: device.uid) else {
            throw EngineError("No microphone found.")
        }
        let capture = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: microphone)
        let output = AVCaptureAudioDataOutput()
        // Float samples for the level meter, already at the recogniser's rate.
        output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM,
                                AVSampleRateKey: session.audioFormat.sampleRate,
                                AVNumberOfChannelsKey: 1,
                                AVLinearPCMBitDepthKey: 32,
                                AVLinearPCMIsFloatKey: true,
                                AVLinearPCMIsBigEndianKey: false,
                                AVLinearPCMIsNonInterleaved: false]
        guard capture.canAddInput(input), capture.canAddOutput(output) else {
            throw EngineError("The microphone's audio format is not supported.")
        }
        let sink = CaptureSink(meter: meter, session: session)
        output.setSampleBufferDelegate(sink, queue: DispatchQueue(label: "de.tobymarks.inlaut.capture", qos: .userInteractive))
        capture.addInput(input)
        capture.addOutput(output)
        capture.startRunning()
        guard capture.isRunning else { throw EngineError("No microphone found.") }
        self.capture = capture
        self.sink = sink
    }

    #if DEBUG
    private func feed(_ path: String, into session: TranscriptionSession) throws {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              let converter = AVAudioConverter(from: file.processingFormat, to: session.audioFormat) else {
            throw EngineError("The microphone's audio format is not supported.")
        }
        try file.read(into: buffer)
        let meter = Meter()
        meter.update(buffer)
        if let converted = Self.convert(buffer, with: converter, to: session.audioFormat) { session.append(converted) }
        self.meter = meter
        startedAt = Date()
    }
    #endif

    /// Loudest sample of the latest buffer (0…1), for the level display.
    var level: Float { meter?.current ?? 0 }

    func stop() -> Take {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        capture?.stopRunning()
        capture = nil
        sink = nil
        startup.firstBufferMs = meter?.firstBufferMs ?? -1
        startup.firstSignalMs = meter?.firstSignalMs ?? -1
        let take = Take(seconds: Date().timeIntervalSince(startedAt), peak: meter?.peak ?? 0, startup: startup)
        meter = nil
        startup = Startup()
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

    nonisolated fileprivate static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        let once = Once()
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            guard once.claim() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }
}

/// Receives the capture session's audio on its own queue and passes it on in
/// the recogniser's format.
private final class CaptureSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let meter: Meter
    private let session: TranscriptionSession
    private let target: AVAudioFormat
    /// Only touched on the capture queue.
    private var converter: AVAudioConverter?

    init(meter: Meter, session: TranscriptionSession) {
        self.meter = meter
        self.session = session
        target = session.audioFormat
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                           into: buffer.mutableAudioBufferList) == noErr else { return }
        meter.update(buffer)
        if format == target {
            session.append(buffer)
            return
        }
        if converter == nil { converter = AVAudioConverter(from: format, to: target) }
        if let converter, let converted = Recorder.convert(buffer, with: converter, to: target) {
            session.append(converted)
        }
    }
}

/// Hands the converter its one input buffer. The input block counts as
/// concurrently executing, so a captured `var` flag does not compile cleanly.
private final class Once: Sendable {
    private let claimed = Atomic<Bool>(false)
    /// True on the first call only.
    func claim() -> Bool { !claimed.exchange(true, ordering: .relaxed) }
}

/// One writer (the audio tap), concurrent readers (the UI). Atomic bit
/// patterns keep the realtime callback free of locks and allocations.
final class Meter: Sendable {
    private let peakBits = Atomic<UInt32>(0)
    private let currentBits = Atomic<UInt32>(0)
    var peak: Float { Float(bitPattern: peakBits.load(ordering: .relaxed)) }
    var current: Float { Float(bitPattern: currentBits.load(ordering: .relaxed)) }

    private let since: UInt64
    private let firstBuffer = Atomic<Int>(-1)
    private let firstSignal = Atomic<Int>(-1)
    /// Milliseconds from `since` to the first buffer and to the first buffer
    /// that is not pure silence; -1 until that happened.
    var firstBufferMs: Int { firstBuffer.load(ordering: .relaxed) }
    var firstSignalMs: Int { firstSignal.load(ordering: .relaxed) }

    init(since: UInt64 = DispatchTime.now().uptimeNanoseconds) { self.since = since }

    func update(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        var loudest: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            loudest = max(loudest, abs(data[i]))
        }
        currentBits.store(loudest.bitPattern, ordering: .relaxed)
        if firstSignal.load(ordering: .relaxed) < 0 {
            let ms = Int((DispatchTime.now().uptimeNanoseconds &- since) / 1_000_000)
            if firstBuffer.load(ordering: .relaxed) < 0 { firstBuffer.store(ms, ordering: .relaxed) }
            if loudest > 0 { firstSignal.store(ms, ordering: .relaxed) }
        }
        peakBits.store(max(peak, loudest).bitPattern, ordering: .relaxed)
    }
}
