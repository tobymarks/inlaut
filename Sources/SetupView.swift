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
        VStack(alignment: .leading, spacing: 24) {
            InlautBrandHeader(title: "Deine Stimme. Direkt als Text.",
                              subtitle: "Einmal einrichten. Danach diktierst du direkt in dein Textfeld. Deine Sprache bleibt auf diesem Mac.")

            VStack(alignment: .leading, spacing: 14) {
                Step(number: 1, done: state.modelState == .ready, title: "Spracherkennung laden") {
                    ModelStatusView(state: state)
                }
                Step(number: 2, done: state.microphoneGranted, title: "Mikrofon erlauben") {
                    if !state.microphoneGranted {
                        Button("Mikrofon erlauben …") { state.requestMicrophone() }
                    }
                }
                if state.trigger == .globe {
                    Step(number: 3, done: !GlobeKeySetting.conflicts, title: "🌐-Taste für Inlaut freigeben") {
                        if GlobeKeySetting.conflicts {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Unter Tastatur „🌐-Taste drücken“ auf „Keine Aktion“ stellen.")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button("Tastatur-Einstellungen öffnen …") { GlobeKeySetting.openKeyboardSettings() }
                            }
                        }
                    }
                }
                Step(number: state.trigger == .globe ? 4 : 3, done: state.accessibilityGranted, title: "Einfügen in andere Apps erlauben") {
                    if !state.accessibilityGranted {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Unter Bedienungshilfen „Inlaut“ einschalten.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Bedienungshilfen öffnen …") { state.requestAccessibility() }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.inlautSurface, in: .rect(cornerRadius: 18))

            HStack {
                Text(state.trigger == .globe
                     ? "Diktieren: **🌐 halten** · zweimal tippen für freihändig"
                     : "Diktieren: **\(state.shortcut.display)** \(state.mode == .hold ? "halten" : "drücken")")
                    .font(.callout)
                    .foregroundStyle(Color.inlautMuted)
                Spacer()
                Button("Fertig", action: done)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(Color.inlautPaper)
        .tint(.inlautAccent)
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
    let number: Int
    let done: Bool
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.inlautAccent : Color.inlautPaper)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.inlautOnAccent)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inlautMuted)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityLabel(done ? "Erledigt" : "Schritt \(number)")
            VStack(alignment: .leading, spacing: 6) {
                Text(title).fontWeight(.semibold).foregroundStyle(Color.inlautInk)
                content
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: fraction).frame(maxWidth: 240)
                    .accessibilityLabel("Sprachmodell herunterladen")
                HStack(spacing: 12) {
                    Text("\(Int(fraction * 100)) % von \(Self.size)").font(.callout).monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Abbrechen") { state.cancelDownload() }.controlSize(.small)
                }
            }
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Wird geladen …").font(.callout).foregroundStyle(.secondary)
            }
        case .installed:
            HStack {
                Text("Auf diesem Mac gespeichert.").font(.callout).foregroundStyle(.secondary)
                if state.engineChoice == .parakeet {
                    Button("Aktivieren") { state.startDownload() }
                }
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
