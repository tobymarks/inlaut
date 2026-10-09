import AppKit
import AVFoundation
import Observation
import os
import ServiceManagement
import Speech

enum Mode: String, CaseIterable, Identifiable {
    case hold, toggle
    var id: String { rawValue }
    var label: String { self == .hold ? String(localized: "Hold to talk") : String(localized: "Press to start/stop") }
}

enum Trigger: String, CaseIterable, Identifiable {
    case globe, shortcut
    var id: String { rawValue }
    var label: String { self == .globe ? String(localized: "🌐 key (fn)") : String(localized: "Key combination") }
}

enum EngineChoice: String, CaseIterable, Identifiable {
    case parakeet, apple
    var id: String { rawValue }
    var label: String {
        switch self {
        case .parakeet: String(localized: "Parakeet – best quality")
        case .apple: String(localized: "Apple – low memory use")
        }
    }
}

/// What the user dictates in. Drives the Parakeet model, Apple's locale,
/// the voice commands and (with #3) the interface language.
enum DictationLanguage: String, CaseIterable, Identifiable {
    case german, english, bilingual
    var id: String { rawValue }

    var label: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        case .bilingual: "Deutsch + English"
        }
    }

    var spoken: Set<SpokenLanguage> {
        switch self {
        case .german: [.german]
        case .english: [.english]
        case .bilingual: [.german, .english]
        }
    }

    /// primeline also handles English and mixed sentences; v2 is only
    /// better for native English speakers (measured in #9/#10).
    var model: SpeechModel { self == .english ? .parakeetV2 : .primeline }

    /// Apple's recogniser takes one locale; mixed speech is mostly German.
    var appleLocale: Locale { Locale(identifier: self == .english ? "en-US" : "de-DE") }

    var commandHelp: String {
        switch self {
        case .german: String(localized: "“neue Zeile” and “neuer Absatz” become line breaks.")
        case .english: String(localized: "“new line” and “new paragraph” become line breaks.")
        case .bilingual: String(localized: "“neue Zeile”, “neuer Absatz”, “new line” and “new paragraph” become line breaks.")
        }
    }

    /// The interface follows German or English; bilingual keeps whatever the
    /// interface currently is.
    var interfaceLanguage: String? {
        switch self {
        case .german: "de"
        case .english: "en"
        case .bilingual: nil
        }
    }

    /// First launch follows the macOS language.
    static var system: DictationLanguage {
        Locale.preferredLanguages.first?.hasPrefix("de") == true ? .german : .english
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

/// A different model on its way in. The current one keeps dictating until
/// the new one is downloaded, verified and loaded.
struct ModelSwitch: Equatable {
    enum Phase: Equatable {
        case downloading(Double)
        case loading
        case failed(String)
    }

    let model: SpeechModel
    var phase: Phase
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
        case .ready: String(localized: "Ready")
        case .recording: String(localized: "Listening …")
        case .transcribing: String(localized: "Transcribing …")
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
        case .preparing: String(localized: "inlaut: preparing")
        case .ready: String(localized: "inlaut: ready")
        case .recording: String(localized: "inlaut: recording")
        case .transcribing: String(localized: "inlaut: transcribing")
        case .failed: String(localized: "inlaut: unavailable")
        }
    }
}

@MainActor
@Observable
final class AppState {
    private(set) var status: Status = .preparing(String(localized: "Starting …")) {
        didSet { updater.isBusy = isDictating }
    }
    /// The Parakeet model in use (or being set up for first use).
    private(set) var model: SpeechModel
    private(set) var modelState: ModelState
    private(set) var modelSwitch: ModelSwitch?
    /// macOS only picks up a new interface language at launch.
    private(set) var interfaceRestartNeeded = false
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
    var language: DictationLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: "language")
            applyLanguage(previous: oldValue)
        }
    }
    var engineChoice: EngineChoice {
        didSet {
            UserDefaults.standard.set(engineChoice.rawValue, forKey: "engine")
            configureEngine()
        }
    }
    /// Keeps every downloaded model on disk, so switching back only loads
    /// (~2 s) instead of downloading again. Only the active one is in memory.
    var keepModels: Bool {
        didSet {
            UserDefaults.standard.set(keepModels, forKey: "keepModels")
            if !keepModels, modelSwitch == nil { ModelStore.removeAll(except: model) }
        }
    }
    var playSounds: Bool {
        didSet { UserDefaults.standard.set(playSounds, forKey: "playSounds") }
    }
    /// "neue Zeile" / "neuer Absatz" become line breaks.
    var voiceCommands: Bool {
        didSet { UserDefaults.standard.set(voiceCommands, forKey: "voiceCommands") }
    }
    /// "Strasse" → "Straße"; off by default where ss is the norm.
    var sharpS: Bool {
        didSet { UserDefaults.standard.set(sharpS, forKey: "sharpS") }
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

    private var apple: AppleSpeechEngine
    private var parakeet: ParakeetEngine
    private var appleReady = false
    private var appleError: String?
    private var applePreparation: Task<Void, Never>?
    private var parakeetPreparation: Task<Void, Never>?
    private var download: Task<Void, Never>?
    private var switchTask: Task<Void, Never>?
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
        // Installs from before the language setting dictated German.
        let existing = defaults.object(forKey: "engine") != nil || SpeechModel.primeline.isInstalled
        let language = DictationLanguage(rawValue: defaults.string(forKey: "language") ?? "")
            ?? (existing ? .german : .system)
        self.language = language
        apple = AppleSpeechEngine(locale: language.appleLocale)
        let model = SpeechModel.with(id: defaults.string(forKey: "model") ?? "") ?? language.model
        self.model = model
        parakeet = ParakeetEngine(model: model)
        // Also clears what an interrupted switch left behind.
        let keepModels = defaults.bool(forKey: "keepModels")
        self.keepModels = keepModels
        if !keepModels { ModelStore.removeAll(except: model) }
        modelState = model.isInstalled ? .installed : .missing
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? true
        voiceCommands = defaults.object(forKey: "voiceCommands") as? Bool ?? true
        sharpS = defaults.object(forKey: "sharpS") as? Bool ?? !["CH", "LI"].contains(Locale.current.region?.identifier)
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
        status = .preparing(String(localized: "Loading speech recognition …"))
        // Independent tasks: Apple's asset installation must never delay a
        // locally installed Parakeet model or its download/setup window.
        prepareApple()
        configureEngine()
        // Finishes a switch the last session did not complete.
        if language.model != model { selectModel(language.model) }
    }

    private func applyLanguage(previous: DictationLanguage) {
        if let code = language.interfaceLanguage {
            // The per-app language, the same one System Settings sets.
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
            interfaceRestartNeeded = Bundle.main.preferredLocalizations.first != code
        }
        selectModel(language.model)
        if language.appleLocale != previous.appleLocale {
            let released = previous.appleLocale
            applePreparation?.cancel()
            applePreparation = nil
            apple = AppleSpeechEngine(locale: language.appleLocale)
            appleReady = false
            appleError = nil
            // Our reservation only; the system keeps assets other apps use.
            Task { _ = await AssetInventory.release(reservedLocale: released) }
            prepareApple()
        }
        updateStatus()
    }

    private func configureEngine() {
        if engineChoice == .apple {
            download?.cancel()
            parakeet.unload()
            if download == nil, parakeetPreparation == nil {
                modelState = model.isInstalled ? .installed : .missing
            }
            prepareApple()
        } else if parakeet.isLoaded {
            modelState = .ready
        } else if model.isInstalled {
            loadParakeet()
        } else if download == nil {
            showSetup()
            startDownload()
        }
        updateStatus()
    }

    func prepareApple() {
        guard !appleReady, applePreparation == nil else { return }
        let engine = apple
        appleError = nil
        applePreparation = Task {
            var failure: Error?
            do { try await engine.prepare() } catch { failure = error }
            // A language change replaced the engine meanwhile.
            guard engine === apple else { return }
            applePreparation = nil
            if let failure {
                appleError = failure.localizedDescription
                log.error("apple prepare failed: \(failure.localizedDescription)")
            } else {
                appleReady = true
            }
            updateStatus()
        }
    }

    private func loadParakeet() {
        guard engineChoice == .parakeet, parakeetPreparation == nil, !parakeet.isLoaded else { return }
        let engine = parakeet
        modelState = .loading
        updateStatus()
        parakeetPreparation = Task {
            let started = Date()
            var failure: Error?
            do { try await engine.prepare() } catch { failure = error }
            parakeetPreparation = nil
            // A model switch replaced the engine meanwhile: start over with the new one.
            guard engine === parakeet else {
                engine.unload()
                configureEngine()
                return
            }
            if let failure {
                log.error("parakeet load failed: \(failure.localizedDescription)")
                modelState = .failed(failure.localizedDescription)
            } else if engineChoice == .parakeet {
                modelState = .ready
                log.notice("parakeet loaded in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            } else {
                parakeet.unload()
                modelState = .installed
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
                try await model.install { fraction in
                    guard self.download != nil else { return }
                    if case .downloading = self.modelState { self.modelState = .downloading(fraction) }
                }
                try Task.checkCancellation()
                modelState = .installed
                loadParakeet()
            } catch is CancellationError {
                modelState = model.isInstalled ? .installed : .missing
            } catch {
                log.error("model download failed: \(error.localizedDescription)")
                modelState = Task.isCancelled
                    ? (model.isInstalled ? .installed : .missing) : .failed(error.localizedDescription)
            }
            updateStatus()
        }
    }

    func cancelDownload() {
        download?.cancel()
    }

    // MARK: - Switching models

    private func selectModel(_ new: SpeechModel) {
        if new == model {
            cancelModelSwitch()
            return
        }
        if modelSwitch?.model == new, switchTask != nil { return }
        cancelModelSwitch()
        if parakeet.isLoaded || model.isInstalled {
            startModelSwitch(to: new)
        } else {
            replaceModel(with: new)
        }
    }

    /// Other models kept on disk next to the active one.
    var otherInstalledModels: [SpeechModel] {
        SpeechModel.catalogue.filter { $0 != model && $0.isInstalled }
    }

    func retryModelSwitch() {
        guard let pending = modelSwitch, switchTask == nil else { return }
        startModelSwitch(to: pending.model)
    }

    /// Stops the switch and removes what it downloaded; the current model stays.
    func cancelModelSwitch() {
        guard let pending = modelSwitch else { return }
        let task = switchTask
        task?.cancel()
        switchTask = nil
        modelSwitch = nil
        Task {
            await task?.value
            if !keepModels, pending.model != model, modelSwitch?.model != pending.model { pending.model.delete() }
        }
    }

    /// Downloads and loads the new model next to the current one, which keeps
    /// dictating. Only when the new one works is the old one deleted, so a
    /// failed or cancelled switch changes nothing.
    private func startModelSwitch(to new: SpeechModel) {
        modelSwitch = ModelSwitch(model: new, phase: .downloading(0))
        switchTask = Task {
            do {
                try await new.install { fraction in
                    guard self.modelSwitch?.model == new, case .downloading = self.modelSwitch?.phase else { return }
                    self.modelSwitch?.phase = .downloading(fraction)
                }
                try Task.checkCancellation()
                var engine: ParakeetEngine?
                if engineChoice == .parakeet {
                    modelSwitch?.phase = .loading
                    let loading = ParakeetEngine(model: new)
                    try await loading.prepare()
                    try Task.checkCancellation()
                    engine = loading
                }
                commitModel(new, engine: engine)
            } catch {
                // A cancelled switch was already cleared by cancelModelSwitch.
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                log.error("model switch failed: \(error.localizedDescription)")
                switchTask = nil
                modelSwitch?.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func commitModel(_ new: SpeechModel, engine: ParakeetEngine?) {
        // An active take keeps its own recognizer until it finishes.
        parakeet.unload()
        parakeet = engine ?? ParakeetEngine(model: new)
        model = new
        UserDefaults.standard.set(new.id, forKey: "model")
        switchTask = nil
        modelSwitch = nil
        if !keepModels { ModelStore.removeAll(except: new) }
        log.notice("switched model")
        modelState = parakeet.isLoaded ? .ready : .installed
        // A load still running for the old engine restarts with the new one.
        if parakeetPreparation == nil { configureEngine() }
        updateStatus()
    }

    /// Nothing usable to keep (first download not finished): swap right away.
    private func replaceModel(with new: SpeechModel) {
        let old = model
        let previous = download
        previous?.cancel()
        parakeet = ParakeetEngine(model: new)
        model = new
        UserDefaults.standard.set(new.id, forKey: "model")
        modelState = new.isInstalled ? .installed : .missing
        Task {
            await previous?.value
            if !keepModels, model != old { old.delete() }
            modelState = model.isInstalled ? .installed : .missing
            // Straight on with the download, without reopening the setup window.
            if engineChoice == .parakeet, !model.isInstalled { startDownload() } else { configureEngine() }
        }
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
            status = .preparing(String(localized: "Loading speech recognition …"))
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

    func relaunch() {
        guard !isDictating else { return }
        // A fresh instance once this one has quit; `open` would otherwise
        // just reactivate the running app.
        let script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, Bundle.main.bundlePath]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            log.error("relaunch failed: \(error.localizedDescription)")
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
            fail(String(localized: "Speech recognition is still loading …"))
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
                if take.peak == 0 { throw EngineError("Only silence – is microphone access missing?") }
                let started = Date()
                let raw = try await session.finish()
                try Task.checkCancellation()
                guard dictationID == id else { return }
                // Length and timing only — the dictated text is never logged.
                log.notice("\(take.seconds, format: .fixed(precision: 1))s audio → \(raw.count) chars in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
                // The user's replacements come last, so they can override ß.
                var text = voiceCommands ? VoiceCommands.apply(to: raw, languages: language.spoken) : raw
                if sharpS, language.spoken.contains(.german) { text = SharpS.apply(to: text) }
                text = replacements.apply(to: text)
                guard !text.isEmpty else {
                    status = .ready
                    indicator.showMessage(String(localized: "Nothing recognized"))
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
