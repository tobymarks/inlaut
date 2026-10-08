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
        Text("Kurzbefehl: \(state.shortcut.display)")
        if let engine = state.activeEngine {
            Text("Erkennung: \(engine.name)")
        }
        switch state.modelState {
        case .downloading(let fraction):
            Text("Parakeet wird geladen: \(Int(fraction * 100)) %")
        case .missing, .failed:
            if state.engineChoice == .parakeet {
                Button("Parakeet-Modell laden …") { state.showSetup() }
            }
        default:
            EmptyView()
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

        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .onAppear { state.refreshPermissions() }
    }
}
