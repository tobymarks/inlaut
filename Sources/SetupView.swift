import AppKit
import SwiftUI

/// First-run window: downloads the speech model and walks through the two
/// permissions. Opened by AppState, which is why it is not a SwiftUI scene.
@MainActor
final class SetupWindow {
    private var window: NSWindow?

    func show(state: AppState) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SetupView(state: state) { [weak self] in
                self?.window?.close()
            }))
            window.title = "Inlaut einrichten"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SetupView: View {
    let state: AppState
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Willkommen bei Inlaut").font(.title2.bold())
                    Text("Diktieren in jedes Textfeld – erkannt auf diesem Mac, nichts verlässt ihn.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Step(done: state.modelState == .ready, title: "Spracherkennung laden") {
                    ModelStatusView(state: state)
                }
                Step(done: state.microphoneGranted, title: "Mikrofon erlauben") {
                    if !state.microphoneGranted {
                        Button("Mikrofon erlauben …") { state.requestMicrophone() }
                    }
                }
                Step(done: state.accessibilityGranted, title: "Einfügen in andere Apps erlauben") {
                    if !state.accessibilityGranted {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Unter Bedienungshilfen „Inlaut“ einschalten.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Bedienungshilfen öffnen …") { state.requestAccessibility() }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("Diktieren: **\(state.shortcut.display)** \(state.mode == .hold ? "halten" : "drücken")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Fertig", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        // Permissions are granted in System Settings; pick that up on return.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermissions()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            state.refreshPermissions()
        }
    }
}

private struct Step<Content: View>: View {
    let done: Bool
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).fontWeight(.medium)
                content
            }
        }
    }
}

/// Download progress, retry and size, shared by setup and settings.
struct ModelStatusView: View {
    let state: AppState

    var body: some View {
        switch state.modelState {
        case .missing:
            HStack {
                Text("Parakeet Deutsch, \(Self.size) einmalig").font(.callout).foregroundStyle(.secondary)
                Button("Laden") { state.startDownload() }
            }
        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 200)
                Text("\(Int(fraction * 100)) % von \(Self.size)").font(.callout).monospacedDigit()
                    .foregroundStyle(.secondary)
                Button("Abbrechen") { state.cancelDownload() }.controlSize(.small)
            }
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Wird geladen …").font(.callout).foregroundStyle(.secondary)
            }
        case .ready:
            Text("Parakeet Deutsch ist bereit.").font(.callout).foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.callout).foregroundStyle(.red)
                Button("Erneut versuchen") { state.startDownload() }
            }
        }
    }

    static let size = ByteCountFormatter.string(fromByteCount: ParakeetModel.totalBytes, countStyle: .file)
}
