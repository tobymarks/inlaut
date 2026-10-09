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
        if state.trigger == .globe {
            Text("Dictate: 🌐 key")
        } else {
            Text("Shortcut: \(state.shortcut.display)")
        }
        if state.isDictating {
            Button("Discard Dictation") { state.cancelDictation() }
        }
        if let engine = state.activeEngine {
            Text("Recognition: \(engine.name)")
        }
        switch state.modelState {
        case .downloading(let fraction):
            Text("Downloading \(state.model.name): \(Int(fraction * 100)) %")
        case .missing, .failed:
            if state.engineChoice == .parakeet {
                Button("Download Parakeet Model …") { state.showSetup() }
            }
        default:
            EmptyView()
        }
        if state.keepModels, state.engineChoice == .parakeet {
            Picker("Language", selection: $state.language) {
                ForEach(DictationLanguage.allCases) { Text($0.label).tag($0) }
            }
        }
        if let pending = state.modelSwitch, case .loading = pending.phase {
            Text("Loading \(pending.model.name) …")
        }
        if let pending = state.modelSwitch, case .downloading(let fraction) = pending.phase {
            Text("Switching to \(pending.model.name): \(Int(fraction * 100)) %")
        }

        if !state.lastText.isEmpty {
            Button("Copy Last Dictation") { state.copyLastText() }
                .help(state.lastText)
        }

        Divider()

        if !state.accessibilityGranted || !state.microphoneGranted {
            Button("Set Up Permissions …") { state.showSetup() }
        }

        Picker("Mode", selection: $state.mode) {
            ForEach(Mode.allCases) { Text($0.label).tag($0) }
        }
        Button("Settings …") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        CheckForUpdatesButton(updater: state.updater)

        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
            .onAppear { state.refreshPermissions() }
    }
}
