import AppKit
import Observation
import os
import ServiceManagement

enum Mode: String, CaseIterable, Identifiable {
    case hold, toggle
    var id: String { rawValue }
    var label: String { self == .hold ? "Halten zum Sprechen" : "Drücken zum Starten/Stoppen" }
}

enum Status: Equatable {
    case preparing(String)
    case ready
    case recording
    case transcribing
    case failed(String)

    var label: String {
        switch self {
        case .preparing(let s): s
        case .ready: "Bereit"
        case .recording: "Hört zu …"
        case .transcribing: "Erkennt …"
        case .failed(let s): s
        }
    }

    var symbol: String {
        switch self {
        case .preparing: "mic.badge.ellipsis"
        case .ready: "mic"
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        case .failed: "mic.slash"
        }
    }
}

@MainActor
@Observable
final class AppState {
    private(set) var status: Status = .preparing("Startet …")
    private(set) var lastText = ""
    private(set) var accessibilityGranted = TextInserter.isTrusted

    var shortcut: Shortcut {
        didSet { save(shortcut, "shortcut"); hotKey.register(shortcut) }
    }
    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    var playSounds: Bool {
        didSet { UserDefaults.standard.set(playSounds, forKey: "playSounds") }
    }
    /// Names and terms the recogniser should prefer.
    var vocabulary: [String] {
        didSet { UserDefaults.standard.set(vocabulary, forKey: "terms") }
    }
    var indicatorPosition: IndicatorPosition {
        didSet {
            UserDefaults.standard.set(indicatorPosition.rawValue, forKey: "indicatorPosition")
            indicator.position = indicatorPosition
        }
    }
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { log.error("launch at login: \(error.localizedDescription)") }
        }
    }

    private let engine: TranscriptionEngine = AppleSpeechEngine()
    private let recorder = Recorder()
    private let hotKey = HotKey()
    private let indicator = RecordingIndicator()
    private var session: TranscriptionSession?
    private let log = Logger(subsystem: "de.tobymarks.inlaut", category: "app")

    /// Shorter takes are treated as an accidental tap and dropped.
    private let minimumSeconds: TimeInterval = 0.3

    init() {
        let defaults = UserDefaults.standard
        shortcut = (defaults.data(forKey: "shortcut")).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .hold
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        // Early builds kept the terms as one newline-separated string.
        vocabulary = defaults.stringArray(forKey: "terms")
            ?? (defaults.string(forKey: "vocabulary") ?? "").split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        indicatorPosition = IndicatorPosition(rawValue: defaults.string(forKey: "indicatorPosition") ?? "") ?? .bottomCenter
        indicator.position = indicatorPosition

        hotKey.onPress = { [weak self] in self?.hotKeyPressed() }
        hotKey.onRelease = { [weak self] in self?.hotKeyReleased() }
        hotKey.register(shortcut)

        Task { await prepare() }
    }

    func prepare() async {
        status = .preparing("Lädt Spracherkennung …")
        do {
            try await engine.prepare()
            status = .ready
        } catch {
            log.error("prepare failed: \(error.localizedDescription)")
            status = .failed(error.localizedDescription)
        }
    }

    /// While the settings field records a new shortcut, the old one must not fire.
    func suspendHotKey(_ suspended: Bool) {
        suspended ? hotKey.unregister() : hotKey.register(shortcut)
    }

    func refreshAccessibility() {
        accessibilityGranted = TextInserter.isTrusted
    }

    func requestAccessibility() {
        TextInserter.requestTrust()
    }

    func copyLastText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastText, forType: .string)
    }

    // MARK: - Dictation flow

    private func hotKeyPressed() {
        switch (mode, status) {
        case (.toggle, .recording): stopAndTranscribe()
        case (_, .ready), (_, .failed): startRecording()
        default: break
        }
    }

    private func hotKeyReleased() {
        if mode == .hold, status == .recording { stopAndTranscribe() }
    }

    private func startRecording() {
        do {
            let session = try engine.begin(vocabulary: vocabulary)
            try recorder.start(into: session)
            self.session = session
            status = .recording
            indicator.showRecording { [recorder] in recorder.level }
            if playSounds { NSSound(named: "Tink")?.play() }
        } catch {
            log.error("start failed: \(error.localizedDescription)")
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        status = .failed(message)
        indicator.showMessage(message)
    }

    private func stopAndTranscribe() {
        guard let session else { return }
        self.session = nil
        let take = recorder.stop()
        if playSounds { NSSound(named: "Pop")?.play() }

        if take.seconds < minimumSeconds {
            Task { await session.cancel() }
            status = .ready
            indicator.hide()
            return
        }
        if take.peak == 0 {
            Task { await session.cancel() }
            fail("Nur Stille – fehlt die Mikrofon-Berechtigung?")
            return
        }

        status = .transcribing
        indicator.showTranscribing()
        Task {
            do {
                let started = Date()
                let text = try await session.finish()
                // Length and timing only — the dictated text is never logged.
                log.notice("\(take.seconds, format: .fixed(precision: 1))s audio → \(text.count) chars in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
                guard !text.isEmpty else {
                    status = .ready
                    indicator.showMessage("Nichts erkannt")
                    return
                }
                // Hide before pasting so the panel never sits over the target.
                indicator.hide()
                lastText = text
                let pasted = await TextInserter.insert(text)
                refreshAccessibility()
                if pasted {
                    status = .ready
                } else {
                    fail("In Zwischenablage – zum Einfügen Bedienungshilfen erlauben")
                    requestAccessibility()
                }
            } catch {
                log.error("transcribe failed: \(error.localizedDescription)")
                fail(error.localizedDescription)
            }
        }
    }

    private func save(_ value: some Encodable, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
