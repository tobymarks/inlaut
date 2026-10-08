import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        Form {
            Section {
                LabeledContent("Kurzbefehl") {
                    ShortcutRecorder(state: state)
                }
                Picker("Modus", selection: $state.mode) {
                    ForEach(Mode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Töne beim Start und Ende", isOn: $state.playSounds)
                Toggle("Beim Anmelden starten", isOn: $state.launchAtLogin)
            }

            Section {
                TextEditor(text: $state.vocabulary)
                    .font(.body)
                    .frame(minHeight: 90)
            } header: {
                Text("Eigene Begriffe")
            } footer: {
                Text("Namen und Fachbegriffe, einer pro Zeile. Die Spracherkennung bevorzugt sie.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Einfügen in andere Apps") {
                    if state.accessibilityGranted {
                        Label("Erlaubt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Bedienungshilfen erlauben …") { state.requestAccessibility() }
                    }
                }
            } footer: {
                Text("Alles wird auf diesem Mac erkannt. Es werden keine Aufnahmen oder Texte gespeichert oder übertragen.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
        .onAppear { state.refreshAccessibility() }
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
