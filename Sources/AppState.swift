import AppKit
import AVFoundation
import Observation
import os
import ServiceManagement

enum Mode: String, CaseIterable, Identifiable {
    case hold, toggle
    var id: String { rawValue }
    var label: String { self == .hold ? "Halten zum Sprechen" : "Drücken zum Starten/Stoppen" }
}

enum Trigger: String, CaseIterable, Identifiable {
    case globe, shortcut
    var id: String { rawValue }
    var label: String { self == .globe ? "🌐-Taste (fn)" : "Tastenkombination" }
}

enum EngineChoice: String, CaseIterable, Identifiable {
    case parakeet, apple
    var id: String { rawValue }
    var label: String {
        switch self {
        case .parakeet: "Parakeet Deutsch – beste Qualität"
        case .apple: "Apple – ohne Download"
        }
    }
}

enum ModelState: Equatable {
    case missing
    case downloading(Double)
    case loading
    case ready
    case failed(String)
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
    private(set) var modelState: ModelState = ParakeetModel.isInstalled ? .loading : .missing
    private(set) var lastText = ""
    private(set) var accessibilityGranted = TextInserter.isTrusted
    private(set) var microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    var trigger: Trigger {
        didSet {
            UserDefaults.standard.set(trigger.rawValue, forKey: "trigger")
            applyTrigger()
        }
    }
    var shortcut: Shortcut {
        didSet { save(shortcut, "shortcut"); applyTrigger() }
    }
    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    var engineChoice: EngineChoice {
        didSet {
            UserDefaults.standard.set(engineChoice.rawValue, forKey: "engine")
            if engineChoice == .parakeet, modelState == .missing { showSetup() }
            updateStatus()
        }
    }
    var playSounds: Bool {
        didSet { UserDefaults.standard.set(playSounds, forKey: "playSounds") }
    }
    var replacements: [Replacement] {
        didSet { save(replacements, "replacements") }
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

    /// The engine dictation actually uses: Parakeet once it is loaded, Apple
    /// until then (or when chosen), so dictating works from the first minute.
    var activeEngine: TranscriptionEngine? {
        if engineChoice == .parakeet, parakeet.isLoaded { return parakeet }
        return appleReady ? apple : nil
    }

    private let apple = AppleSpeechEngine()
    private let parakeet = ParakeetEngine()
    private var appleReady = false
    private var download: Task<Void, Never>?
    private let recorder = Recorder()
    private let hotKey = HotKey()
    private let globeKey = GlobeKeyTrigger()
    private let indicator = RecordingIndicator()
    private let setupWindow = SetupWindow()
    private var session: TranscriptionSession?
    private let log = Logger(subsystem: "de.tobymarks.inlaut", category: "app")

    /// Shorter takes are treated as an accidental tap and dropped.
    private let minimumSeconds: TimeInterval = 0.3
    /// People finish the last syllable just after letting go of the key.
    private let trailingAudio: Duration = .milliseconds(150)

    init() {
        let defaults = UserDefaults.standard
        trigger = Trigger(rawValue: defaults.string(forKey: "trigger") ?? "") ?? .shortcut
        shortcut = defaults.data(forKey: "shortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        mode = Mode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .hold
        engineChoice = EngineChoice(rawValue: defaults.string(forKey: "engine") ?? "") ?? .parakeet
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        replacements = defaults.data(forKey: "replacements")
            .flatMap { try? JSONDecoder().decode([Replacement].self, from: $0) } ?? []
        indicatorPosition = IndicatorPosition(rawValue: defaults.string(forKey: "indicatorPosition") ?? "") ?? .bottomCenter
        indicator.position = indicatorPosition

        hotKey.onPress = { [weak self] in self?.hotKeyPressed() }
        hotKey.onRelease = { [weak self] in self?.hotKeyReleased() }
        globeKey.onStart = { [weak self] in self?.globeStart() }
        globeKey.onStop = { [weak self] in self?.globeStop() }
        globeKey.onCancel = { [weak self] in self?.discardRecording() }
        applyTrigger()

        Task { await start() }
    }

    private func start() async {
        status = .preparing("Lädt Spracherkennung …")
        await prepareApple()
        if ParakeetModel.isInstalled {
            await loadParakeet()
        } else if engineChoice == .parakeet {
            showSetup()
            startDownload()
        }
        updateStatus()
    }

    func prepareApple() async {
        do {
            try await apple.prepare()
            appleReady = true
        } catch {
            log.error("apple prepare failed: \(error.localizedDescription)")
        }
        updateStatus()
    }

    private func loadParakeet() async {
        modelState = .loading
        updateStatus()
        do {
            let started = Date()
            try await parakeet.prepare()
            log.notice("parakeet loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            modelState = .ready
        } catch {
            log.error("parakeet load failed: \(error.localizedDescription)")
            modelState = .failed(error.localizedDescription)
        }
        updateStatus()
    }

    func startDownload() {
        guard download == nil, !parakeet.isLoaded else { return }
        modelState = .downloading(0)
        updateStatus()
        download = Task {
            defer { download = nil }
            do {
                try await ParakeetModel.install { [weak self] fraction in
                    self?.modelState = .downloading(fraction)
                }
                await loadParakeet()
            } catch is CancellationError {
                modelState = .missing
            } catch {
                log.error("model download failed: \(error.localizedDescription)")
                modelState = Task.isCancelled ? .missing : .failed(error.localizedDescription)
            }
            updateStatus()
        }
    }

    func cancelDownload() {
        download?.cancel()
    }

    /// Ready whenever some engine can take a dictation; only the menu shows
    /// that Parakeet is still on its way.
    private func updateStatus() {
        switch status {
        case .recording, .transcribing: return
        default: break
        }
        if activeEngine != nil {
            status = .ready
        } else if case .failed(let message) = modelState {
            status = .failed(message)
        } else {
            status = .preparing("Lädt Spracherkennung …")
        }
    }

    func showSetup() {
        refreshPermissions()
        setupWindow.show(state: self)
    }

    /// Only the chosen trigger is active; the other one is fully switched off.
    private func applyTrigger() {
        switch trigger {
        case .shortcut:
            globeKey.stop()
            hotKey.register(shortcut)
        case .globe:
            hotKey.unregister()
            globeKey.start()
        }
    }

    /// While the settings field records a new shortcut, the old one must not fire.
    func suspendHotKey(_ suspended: Bool) {
        if suspended { hotKey.unregister() } else { applyTrigger() }
    }

    func refreshPermissions() {
        accessibilityGranted = TextInserter.isTrusted
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestAccessibility() {
        TextInserter.requestTrust()
    }

    func requestMicrophone() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshPermissions()
        }
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

    private func globeStart() {
        switch status {
        case .ready, .failed: startRecording()
        default: break
        }
    }

    private func globeStop() {
        if status == .recording { stopAndTranscribe() }
    }

    /// fn turned out to be part of fn+key: drop the take without a sound.
    private func discardRecording() {
        guard let session else { return }
        self.session = nil
        _ = recorder.stop()
        Task { await session.cancel() }
        indicator.hide()
        status = .ready
    }

    private func startRecording() {
        guard let engine = activeEngine else {
            fail("Spracherkennung lädt noch …")
            return
        }
        do {
            let session = try engine.begin()
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
        status = .transcribing
        indicator.showTranscribing()
        if playSounds { NSSound(named: "Pop")?.play() }

        Task {
            try? await Task.sleep(for: trailingAudio)
            let take = recorder.stop()
            if take.seconds < minimumSeconds {
                await session.cancel()
                status = .ready
                indicator.hide()
                return
            }
            if take.peak == 0 {
                await session.cancel()
                fail("Nur Stille – fehlt die Mikrofon-Berechtigung?")
                return
            }
            do {
                let started = Date()
                let raw = try await session.finish()
                // Length and timing only — the dictated text is never logged.
                log.notice("\(take.seconds, format: .fixed(precision: 1))s audio → \(raw.count) chars in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
                let text = replacements.apply(to: raw)
                guard !text.isEmpty else {
                    status = .ready
                    indicator.showMessage("Nichts erkannt")
                    return
                }
                // Hide before pasting so the panel never sits over the target.
                indicator.hide()
                lastText = text
                let pasted = await TextInserter.insert(text)
                refreshPermissions()
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
