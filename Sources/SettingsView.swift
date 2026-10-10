import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    private static let allModelsSize = ByteCountFormatter.string(
        fromByteCount: SpeechModel.catalogue.reduce(0) { $0 + $1.totalBytes }, countStyle: .file)

    var body: some View {
        VStack(spacing: 0) {
            InlautBrandHeader(title: "Dictate your way.",
                              subtitle: "Recognition, keys and words – set up to suit you.")
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 20)
            Form {
                Section("Speech Recognition") {
                    Picker("Language", selection: $state.language) {
                        ForEach(DictationLanguage.allCases) { Text($0.label).tag($0) }
                    }
                    if state.interfaceRestartNeeded {
                        HStack {
                            Text("The interface switches language after a restart.")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restart Now") { state.relaunch() }
                                .disabled(state.isDictating)
                        }
                    }
                    Picker("Engine", selection: $state.engineChoice) {
                        ForEach(EngineChoice.allCases) { Text($0.label).tag($0) }
                    }
                    if state.engineChoice == .parakeet {
                        LabeledContent("Model") { ModelStatusView(state: state) }
                        // Only matters once the catalogue offers a second model again.
                        if SpeechModel.catalogue.count > 1 {
                            Toggle(isOn: $state.keepModels) {
                                Text("Keep both models")
                                Text("For anyone who often switches between Deutsch and English: switching from the menu then takes a few seconds instead of a new download. If you mix languages, “Deutsch + English” suits you better. Needs up to \(Self.allModelsSize) on this Mac in total.")
                            }
                        }
                    }
                }

                Section("Trigger") {
                    Picker("Dictate with", selection: $state.trigger) {
                        ForEach(Trigger.allCases) { Text($0.label).tag($0) }
                    }
                    switch state.trigger {
                    case .globe:
                        GlobeKeyHelp()
                    case .shortcut:
                        ShortcutRecorder(state: state)
                        Picker("Mode", selection: $state.mode) {
                            ForEach(Mode.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }

                Section("Behavior") {
                    Picker("Indicator while dictating", selection: $state.indicatorPosition) {
                        ForEach(IndicatorPosition.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Sounds at start and end", isOn: $state.playSounds)
                    Toggle("Launch at login", isOn: $state.launchAtLogin)
                }

                Section {
                    Toggle(isOn: $state.voiceCommands) {
                        Text("Lines and paragraphs by voice")
                        Text(state.language.commandHelp)
                    }
                    if state.language.spoken.contains(.german) {
                        Toggle(isOn: $state.sharpS) {
                            Text("ß instead of ss")
                            Text("Writes unambiguous words such as Straße, groß or Grüße with ß.")
                        }
                    }
                }

                Section {
                    ReplacementsField(rules: $state.replacements)
                } header: {
                    Text("Replacements")
                } footer: {
                    Text("Fixes what recognition regularly gets wrong – whole words, case-insensitive. A rule can include the word before it: “das Damm → das DAM” leaves a real “Damm” alone.")
                        .foregroundStyle(.secondary)
                }

                UpdateSettingsView(updater: state.updater)

                Section {
                    LabeledContent("Microphone") {
                        if state.microphoneGranted {
                            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Color.inlautAccent)
                        } else {
                            Button("Allow …") { state.requestMicrophone() }
                        }
                    }
                    LabeledContent("Pasting into other apps") {
                        if state.accessibilityGranted {
                            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Color.inlautAccent)
                        } else {
                            Button("Allow Accessibility …") { state.requestAccessibility() }
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Everything is recognized on this Mac. No recordings or texts are stored or sent.")
                        Text(Self.markdown(String(localized: "Speech recognition: \(state.model.credit) · [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0)")))
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

    /// Links inside an interpolated credit line are not parsed by Text.
    private static func markdown(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string)) ?? AttributedString(string)
    }
}

/// How the 🌐 key works, and a warning while macOS still uses it itself.
private struct GlobeKeyHelp: View {
    @State private var conflicts = GlobeKeySetting.conflicts

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("**Hold** to talk, release to paste. **Double-tap** for hands-free dictation, a single tap ends it. 🌐 together with another key keeps working as fn.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if conflicts {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("macOS currently uses the 🌐 key to \(GlobeKeySetting.actionName). Under Keyboard, set “Press 🌐 key to” to **Do Nothing**.")
                            .font(.callout)
                        Button("Open Keyboard Settings …") { GlobeKeySetting.openKeyboardSettings() }
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
        LabeledContent("Shortcut") {
            Button(recording ? String(localized: "Press a key combination …") : state.shortcut.display) {
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
                ? String(localized: "macOS already uses \(keys) for \(name). Please choose another combination – or turn off the system shortcut under Keyboard → Keyboard Shortcuts.")
                : String(localized: "macOS also uses \(keys) for \(name) – they may get in each other's way."), refused)
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
