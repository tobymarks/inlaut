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
        case .apple: "Apple – geringer Speicherbedarf"
        }
    }
}

enum ModelState: Equatable {
    case missing
    case installed
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

    /// Brand template with distinct, monochrome status badges (scripts/sync-brand.py).
    var menuBarImage: String {
        switch self {
        case .preparing: "menubar-preparing"
        case .ready: "menubar-ready"
        case .recording: "menubar-recording"
        case .transcribing: "menubar-transcribing"
        case .failed: "menubar-failed"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .preparing: "inlaut: wird vorbereitet"
        case .ready: "inlaut: bereit"
        case .recording: "inlaut: nimmt auf"
        case .transcribing: "inlaut: erkennt"
        case .failed: "inlaut: nicht verfügbar"
        }
    }
}

@MainActor
@Observable
final class AppState {
    private(set) var status: Status = .preparing("Startet …") {
        didSet { updater.isBusy = isDictating }
    }
    private(set) var modelState: ModelState = ParakeetModel.isInstalled ? .installed : .missing
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
            configureEngine()
        }
    }
    var playSounds: Bool {
        didSet { UserDefaults.standard.set(playSounds, forKey: "playSounds") }
    }
    /// "neue Zeile" / "neuer Absatz" become line breaks.
    var voiceCommands: Bool {
        didSet { UserDefaults.standard.set(voiceCommands, forKey: "voiceCommands") }
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
    private var appleError: String?
    private var applePreparation: Task<Void, Never>?
    private var parakeetPreparation: Task<Void, Never>?
    private var download: Task<Void, Never>?
    let updater = AppUpdater()
    private let recorder = Recorder()
    private let hotKey = HotKey()
    private let globeKey = GlobeKeyTrigger()
    private let indicator = RecordingIndicator()
    private let setupWindow = SetupWindow()
    private var session: TranscriptionSession?
    private var transcription: Task<Void, Never>?
    private var dictationID: UUID?
    private var pasteTarget: TextInserter.Target?
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
        voiceCommands = defaults.object(forKey: "voiceCommands") as? Bool ?? true
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

        Task { start() }
    }

    private func start() {
        status = .preparing("Lädt Spracherkennung …")
        // Independent tasks: Apple's asset installation must never delay a
        // locally installed Parakeet model or its download/setup window.
        prepareApple()
        configureEngine()
    }

    private func configureEngine() {
        if engineChoice == .apple {
            download?.cancel()
            parakeet.unload()
            if download == nil, parakeetPreparation == nil {
                modelState = ParakeetModel.isInstalled ? .installed : .missing
            }
            prepareApple()
        } else if parakeet.isLoaded {
            modelState = .ready
        } else if ParakeetModel.isInstalled {
            loadParakeet()
        } else if download == nil {
            showSetup()
            startDownload()
        }
        updateStatus()
    }

    func prepareApple() {
        guard !appleReady, applePreparation == nil else { return }
        appleError = nil
        applePreparation = Task {
            defer { applePreparation = nil }
            do {
                try await apple.prepare()
                appleReady = true
            } catch {
                appleError = error.localizedDescription
                log.error("apple prepare failed: \(error.localizedDescription)")
            }
            updateStatus()
        }
    }

    private func loadParakeet() {
        guard engineChoice == .parakeet, parakeetPreparation == nil, !parakeet.isLoaded else { return }
        modelState = .loading
        updateStatus()
        parakeetPreparation = Task {
            defer { parakeetPreparation = nil }
            do {
                let started = Date()
                try await parakeet.prepare()
                if engineChoice == .parakeet {
                    modelState = .ready
                    log.notice("parakeet loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
                } else {
                    parakeet.unload()
                    modelState = .installed
                }
            } catch {
                log.error("parakeet load failed: \(error.localizedDescription)")
                modelState = .failed(error.localizedDescription)
            }
            updateStatus()
        }
    }

    func startDownload() {
        guard download == nil, parakeetPreparation == nil, !parakeet.isLoaded else { return }
        modelState = .downloading(0)
        updateStatus()
        download = Task {
            defer { download = nil }
            do {
                try await ParakeetModel.install { fraction in
                    guard self.download != nil else { return }
                    if case .downloading = self.modelState { self.modelState = .downloading(fraction) }
                }
                try Task.checkCancellation()
                modelState = .installed
                loadParakeet()
            } catch is CancellationError {
                modelState = ParakeetModel.isInstalled ? .installed : .missing
            } catch {
                log.error("model download failed: \(error.localizedDescription)")
                modelState = Task.isCancelled
                    ? (ParakeetModel.isInstalled ? .installed : .missing) : .failed(error.localizedDescription)
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
        } else if engineChoice == .apple, let appleError {
            status = .failed(appleError)
        } else if engineChoice == .parakeet, case .failed(let message) = modelState {
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

    var isDictating: Bool { status == .recording || status == .transcribing }

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
        cancelDictation()
    }

    func cancelDictation() {
        guard isDictating else { return }
        let cancelledSession = session
        dictationID = nil
        transcription?.cancel()
        transcription = nil
        self.session = nil
        pasteTarget = nil
        _ = recorder.stop()
        Task { await cancelledSession?.cancel() }
        indicator.hide()
        status = .ready
        updateStatus()
    }

    private func startRecording() {
        guard let engine = activeEngine else {
            fail("Spracherkennung lädt noch …")
            return
        }
        do {
            pasteTarget = TextInserter.captureTarget()
            self.session = try ManagedSession.start(engine: engine) { try recorder.start(into: $0) }
            dictationID = UUID()
            status = .recording
            indicator.showRecording { [recorder] in recorder.level }
            if playSounds { NSSound(named: "Tink")?.play() }
        } catch {
            let failedSession = session
            session = nil
            pasteTarget = nil
            _ = recorder.stop()
            Task { await failedSession?.cancel() }
            log.error("start failed: \(error.localizedDescription)")
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        status = .failed(message)
        indicator.showMessage(message)
    }

    private func stopAndTranscribe() {
        guard let session, let id = dictationID, status == .recording else { return }
        let target = pasteTarget
        status = .transcribing
        indicator.showTranscribing()

        transcription = Task {
            defer {
                if dictationID == id {
                    self.session = nil
                    transcription = nil
                    dictationID = nil
                    pasteTarget = nil
                }
            }
            do {
                try await Task.sleep(for: trailingAudio)
                guard dictationID == id else { return }
                let take = recorder.stop()
                // Play after closing the microphone, not into the trailing audio.
                if playSounds { NSSound(named: "Pop")?.play() }
                if take.seconds < minimumSeconds {
                    await session.cancel()
                    guard dictationID == id else { return }
                    status = .ready
                    updateStatus()
                    indicator.hide()
                    return
                }
                if take.peak == 0 { throw EngineError("Nur Stille – fehlt die Mikrofon-Berechtigung?") }
                let started = Date()
                let raw = try await session.finish()
                try Task.checkCancellation()
                guard dictationID == id else { return }
                // Length and timing only — the dictated text is never logged.
                log.notice("\(take.seconds, format: .fixed(precision: 1))s audio → \(raw.count) chars in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
                let text = replacements.apply(to: voiceCommands ? VoiceCommands.apply(to: raw) : raw)
                guard !text.isEmpty else {
                    status = .ready
                    indicator.showMessage("Nichts erkannt")
                    return
                }
                // Hide before pasting so the panel never sits over the target.
                indicator.hide()
                lastText = text
                let result = try await TextInserter.insert(text, target: target)
                guard dictationID == id else { return }
                refreshPermissions()
                switch result {
                case .inserted:
                    status = .ready
                    updateStatus()
                case .copied(let message):
                    fail(message)
                    if !accessibilityGranted { requestAccessibility() }
                }
            } catch {
                guard dictationID == id else { return }
                _ = recorder.stop()
                await session.cancel()
                guard dictationID == id else { return }
                log.error("transcribe failed: \(error.localizedDescription)")
                fail(error.localizedDescription)
            }
        }
    }

    private func save(_ value: some Encodable, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
