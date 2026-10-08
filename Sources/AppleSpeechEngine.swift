@preconcurrency import AVFoundation
import Speech

/// macOS 26+ on-device recogniser (SpeechAnalyzer + SpeechTranscriber).
/// The model lives in a system service, so this app stays at a few MB of RAM.
@MainActor
final class AppleSpeechEngine: TranscriptionEngine {
    let name = "Apple (macOS)"
    private let locale: Locale
    private var resolvedLocale: Locale?
    private var format: AVAudioFormat?

    init(locale: Locale = Locale(identifier: "de-DE")) {
        self.locale = locale
    }

    func prepare() async throws {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw EngineError("Die Sprache \(locale.identifier) wird von der Spracherkennung nicht unterstützt.")
        }
        let transcriber = Self.makeTranscriber(supported)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw EngineError("Kein passendes Audioformat für die Spracherkennung.")
        }
        resolvedLocale = supported
        self.format = format
    }

    func begin() throws -> TranscriptionSession {
        guard let resolvedLocale, let format else { throw EngineError("Spracherkennung ist noch nicht bereit.") }
        return AppleSpeechSession(transcriber: Self.makeTranscriber(resolvedLocale), format: format)
    }

    nonisolated private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        // No volatile results: only final text is needed, which keeps the
        // recogniser from re-decoding the same audio over and over.
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    }
}

final class AppleSpeechSession: TranscriptionSession, @unchecked Sendable {
    let audioFormat: AVAudioFormat
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let analysis: Task<Void, Error>
    private let collected: Task<String, Error>

    init(transcriber: SpeechTranscriber, format: AVAudioFormat) {
        audioFormat = format
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        // Subscribe before the analyzer starts so no result is missed.
        collected = Task {
            var parts: [String] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(text) }
            }
            return parts.joined(separator: " ")
        }
        // Contextual strings (custom vocabulary) were tried and had no effect
        // on SpeechTranscriber's output; Replacements cover that instead.
        analysis = Task {
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream)
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        input.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async throws -> String {
        input.finish()
        try await analysis.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collected.value
    }

    func cancel() async {
        input.finish()
        analysis.cancel()
        await analyzer.cancelAndFinishNow()
        collected.cancel()
    }
}
