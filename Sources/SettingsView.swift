import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            InlautBrandHeader(title: "So diktierst du.",
                              subtitle: "Spracherkennung, Tasten und Wörter – passend zu dir.")
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 20)
            Form {
                Section("Spracherkennung") {
                    Picker("Engine", selection: $state.engineChoice) {
                        ForEach(EngineChoice.allCases) { Text($0.label).tag($0) }
                    }
                    if state.engineChoice == .parakeet {
                        Picker("Modell", selection: Binding(get: { state.selectedModel },
                                                            set: { state.selectModel($0) })) {
                            ForEach(SpeechModel.catalogue) { Text($0.name).tag($0) }
                        }
                        LabeledContent("Status") { ModelStatusView(state: state) }
                        Toggle(isOn: $state.keepModels) {
                            Text("Beide Modelle behalten")
                            Text("Für alle, die oft wechseln: Umschalten im Menü dauert dann nur ein paar Sekunden statt eines neuen Downloads. Braucht zusammen bis zu \(ByteCountFormatter.string(fromByteCount: SpeechModel.catalogue.reduce(0) { $0 + $1.totalBytes }, countStyle: .file)) auf diesem Mac.")
                        }
                    }
                }

                Section("Auslösen") {
                    Picker("Diktieren mit", selection: $state.trigger) {
                        ForEach(Trigger.allCases) { Text($0.label).tag($0) }
                    }
                    switch state.trigger {
                    case .globe:
                        GlobeKeyHelp()
                    case .shortcut:
                        ShortcutRecorder(state: state)
                        Picker("Modus", selection: $state.mode) {
                            ForEach(Mode.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }

                Section("Verhalten") {
                    Picker("Anzeige beim Diktieren", selection: $state.indicatorPosition) {
                        ForEach(IndicatorPosition.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Töne beim Start und Ende", isOn: $state.playSounds)
                    Toggle("Beim Anmelden starten", isOn: $state.launchAtLogin)
                }

                Section {
                    Toggle(isOn: $state.voiceCommands) {
                        Text("Zeilen und Absätze per Sprache")
                        Text("„neue Zeile“ und „neuer Absatz“ werden zu Umbrüchen.")
                    }
                    Toggle(isOn: $state.sharpS) {
                        Text("ß statt ss")
                        Text("Schreibt eindeutige Wörter wie Straße, groß oder Grüße mit ß.")
                    }
                }

                Section {
                    ReplacementsField(rules: $state.replacements)
                } header: {
                    Text("Ersetzungen")
                } footer: {
                    Text("Korrigiert, was die Erkennung regelmäßig falsch schreibt – ganze Wörter, Groß-/Kleinschreibung egal.")
                        .foregroundStyle(.secondary)
                }

                UpdateSettingsView(updater: state.updater)

                Section {
                    LabeledContent("Mikrofon") {
                        if state.microphoneGranted {
                            Label("Erlaubt", systemImage: "checkmark.circle.fill").foregroundStyle(Color.inlautAccent)
                        } else {
                            Button("Erlauben …") { state.requestMicrophone() }
                        }
                    }
                    LabeledContent("Einfügen in andere Apps") {
                        if state.accessibilityGranted {
                            Label("Erlaubt", systemImage: "checkmark.circle.fill").foregroundStyle(Color.inlautAccent)
                        } else {
                            Button("Bedienungshilfen erlauben …") { state.requestAccessibility() }
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Alles wird auf diesem Mac erkannt. Es werden keine Aufnahmen oder Texte gespeichert oder übertragen.")
                        Text(LocalizedStringKey("Spracherkennung: \(state.model.credit) · [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (Apache 2.0) · ONNX Runtime (MIT)"))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Color.inlautPaper)
        .tint(.inlautAccent)
        .frame(width: 560, height: 740)
        .onAppear { state.refreshPermissions() }
    }
}

/// How the 🌐 key works, and a warning while macOS still uses it itself.
private struct GlobeKeyHelp: View {
    @State private var conflicts = GlobeKeySetting.conflicts

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("**Halten** zum Sprechen, loslassen fügt ein. **Zweimal tippen** zum freihändigen Diktieren, einmal tippen beendet. 🌐 zusammen mit einer anderen Taste bleibt normale fn-Nutzung.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if conflicts {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("macOS lässt die 🌐-Taste gerade \(GlobeKeySetting.actionName). Stell unter Tastatur „🌐-Taste drücken“ auf **Keine Aktion**.")
                            .font(.callout)
                        Button("Tastatur-Einstellungen öffnen …") { GlobeKeySetting.openKeyboardSettings() }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            conflicts = GlobeKeySetting.conflicts
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            conflicts = GlobeKeySetting.conflicts
        }
    }
}

/// Click, then press the new key combination. Esc cancels. A combination
/// macOS itself uses is refused; a commonly taken one gets a hint.
private struct ShortcutRecorder: View {
    let state: AppState
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: (text: String, refused: Bool)?

    var body: some View {
        LabeledContent("Kurzbefehl") {
            Button(recording ? "Tastenkombination drücken …" : state.shortcut.display) {
                recording ? stop() : start()
            }
            .monospaced(!recording)
        }
        .onAppear { describe(ShortcutConflicts.check(state.shortcut), refused: false) }
        .onDisappear { stop() }
        if let message {
            Label(message.text, systemImage: message.refused ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(message.refused ? .red : .orange)
        }
    }

    private func start() {
        recording = true
        message = nil
        state.suspendHotKey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc
                stop()
            } else if let shortcut = Shortcut(event: event) {
                let finding = ShortcutConflicts.check(shortcut)
                if case .system = finding {
                    describe(finding, for: shortcut, refused: true)
                } else {
                    state.shortcut = shortcut
                    describe(finding, refused: false)
                }
                stop()
            }
            return nil
        }
    }

    private func describe(_ finding: ShortcutConflicts.Finding?, for shortcut: Shortcut? = nil, refused: Bool) {
        let keys = (shortcut ?? state.shortcut).display
        switch finding {
        case .system(let name):
            message = (refused
                ? "\(keys) nutzt macOS schon für \(name). Bitte eine andere Kombination wählen – oder den Systemkurzbefehl unter Tastatur → Tastaturkurzbefehle abschalten."
                : "\(keys) nutzt macOS auch für \(name) – das kann sich in die Quere kommen.", refused)
        case .commonApp(let hint):
            message = (hint, false)
        case nil:
            message = nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { state.suspendHotKey(false) }
        recording = false
    }
}
