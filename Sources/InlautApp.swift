import AppKit
import SwiftUI

@main
struct InlautApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(state.status.menuBarImage)
                .renderingMode(.template)
                .accessibilityLabel(state.status.accessibilityLabel)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state)
        }
    }
}

private struct MenuContent: View {
    @Bindable var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(state.status.label)
        Text(state.trigger == .globe ? "Diktieren: 🌐-Taste" : "Kurzbefehl: \(state.shortcut.display)")
        if state.isDictating {
            Button("Diktat verwerfen") { state.cancelDictation() }
        }
        if let engine = state.activeEngine {
            Text("Erkennung: \(engine.name)")
        }
        switch state.modelState {
        case .downloading(let fraction):
            Text("\(state.model.name) wird geladen: \(Int(fraction * 100)) %")
        case .missing, .failed:
            if state.engineChoice == .parakeet {
                Button("Parakeet-Modell laden …") { state.showSetup() }
            }
        default:
            EmptyView()
        }
        if state.keepModels, state.engineChoice == .parakeet {
            Picker("Sprache", selection: $state.language) {
                ForEach(DictationLanguage.allCases) { Text($0.label).tag($0) }
            }
        }
        if let pending = state.modelSwitch, case .loading = pending.phase {
            Text("\(pending.model.name) wird geladen …")
        }
        if let pending = state.modelSwitch, case .downloading(let fraction) = pending.phase {
            Text("Wechsel zu \(pending.model.name): \(Int(fraction * 100)) %")
        }

        if !state.lastText.isEmpty {
            Button("Letztes Diktat kopieren") { state.copyLastText() }
                .help(state.lastText)
        }

        Divider()

        if !state.accessibilityGranted || !state.microphoneGranted {
            Button("Berechtigungen einrichten …") { state.showSetup() }
        }

        Picker("Modus", selection: $state.mode) {
            ForEach(Mode.allCases) { Text($0.label).tag($0) }
        }
        Button("Einstellungen …") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        CheckForUpdatesButton(updater: state.updater)

        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .onAppear { state.refreshPermissions() }
    }
}
