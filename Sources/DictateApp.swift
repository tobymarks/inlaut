import AppKit
import SwiftUI

@main
struct DictateApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            Image(systemName: state.status.symbol)
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

        if !state.lastText.isEmpty {
            Button("Letztes Diktat kopieren") { state.copyLastText() }
                .help(state.lastText)
        }

        Divider()

        if !state.accessibilityGranted {
            Button("Bedienungshilfen erlauben (für automatisches Einfügen) …") {
                state.requestAccessibility()
            }
        }
        if case .failed = state.status {
            Button("Spracherkennung neu laden") { Task { await state.prepare() } }
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
            .onAppear { state.refreshAccessibility() }
    }
}
