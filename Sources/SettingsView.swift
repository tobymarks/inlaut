import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section("Spracherkennung") {
                Picker("Engine", selection: $state.engineChoice) {
                    ForEach(EngineChoice.allCases) { Text($0.label).tag($0) }
                }
                if state.engineChoice == .parakeet {
                    LabeledContent("Modell") { ModelStatusView(state: state) }
                }
            }

            Section {
                LabeledContent("Kurzbefehl") {
                    ShortcutRecorder(state: state)
                }
                Picker("Modus", selection: $state.mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Anzeige beim Diktieren", selection: $state.indicatorPosition) {
                    ForEach(IndicatorPosition.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Töne beim Start und Ende", isOn: $state.playSounds)
                Toggle("Beim Anmelden starten", isOn: $state.launchAtLogin)
            }

            Section {
                ReplacementsField(rules: $state.replacements)
            } header: {
                Text("Ersetzungen")
            } footer: {
                Text("Korrigiert, was die Erkennung regelmäßig falsch schreibt – ganze Wörter, Groß-/Kleinschreibung egal.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Mikrofon") {
                    if state.microphoneGranted {
                        Label("Erlaubt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Erlauben …") { state.requestMicrophone() }
                    }
                }
                LabeledContent("Einfügen in andere Apps") {
                    if state.accessibilityGranted {
                        Label("Erlaubt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Bedienungshilfen erlauben …") { state.requestAccessibility() }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Alles wird auf diesem Mac erkannt. Es werden keine Aufnahmen oder Texte gespeichert oder übertragen.")
                    Text("Spracherkennung: [parakeet-primeline](https://huggingface.co/primeline/parakeet-primeline) (primeline) auf Basis von [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), beide CC BY 4.0 · [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) (Apache 2.0) · ONNX Runtime (MIT)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize()
        .onAppear { state.refreshPermissions() }
    }
}

/// Click, then press the new key combination. Esc cancels.
private struct ShortcutRecorder: View {
    let state: AppState
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Tastenkombination drücken …" : state.shortcut.display) {
            recording ? stop() : start()
        }
        .monospaced(!recording)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        state.suspendHotKey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc
                stop()
            } else if let shortcut = Shortcut(event: event) {
                state.shortcut = shortcut
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { state.suspendHotKey(false) }
        recording = false
    }
}
