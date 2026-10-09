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
            window.title = String(localized: "Set Up inlaut")
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
            InlautBrandHeader(title: "Your voice. Straight to text.",
                              subtitle: "Set it up once. Then dictate straight into any text field. Your voice stays on this Mac.")

            VStack(alignment: .leading, spacing: 14) {
                Step(number: 1, done: state.modelState == .ready || state.modelState == .resting, title: "Download speech recognition") {
                    ModelStatusView(state: state)
                }
                Step(number: 2, done: state.microphoneGranted, title: "Allow microphone") {
                    if !state.microphoneGranted {
                        Button("Allow Microphone …") { state.requestMicrophone() }
                    }
                }
                if state.trigger == .globe {
                    Step(number: 3, done: !GlobeKeySetting.conflicts, title: "Free up the 🌐 key for inlaut") {
                        if GlobeKeySetting.conflicts {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Under Keyboard, set “Press 🌐 key to” to “Do Nothing”.")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button("Open Keyboard Settings …") { GlobeKeySetting.openKeyboardSettings() }
                            }
                        }
                    }
                }
                Step(number: state.trigger == .globe ? 4 : 3, done: state.accessibilityGranted, title: "Allow pasting into other apps") {
                    if !state.accessibilityGranted {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Turn on “inlaut” under Accessibility.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Open Accessibility Settings …") { state.requestAccessibility() }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.inlautSurface, in: .rect(cornerRadius: 18))

            HStack {
                Group {
                    if state.trigger == .globe {
                        Text("Dictate: **hold 🌐** · double-tap for hands-free")
                    } else if state.mode == .hold {
                        Text("Dictate: hold **\(state.shortcut.display)**")
                    } else {
                        Text("Dictate: press **\(state.shortcut.display)**")
                    }
                }
                    .font(.callout)
                    .foregroundStyle(Color.inlautMuted)
                Spacer()
                Button("Done", action: done)
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
    let title: LocalizedStringKey
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
            .accessibilityLabel(done ? Text("Completed") : Text("Step \(number)"))
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
        VStack(alignment: .leading, spacing: 8) {
            current
            ForEach(state.otherInstalledModels) { model in
                Text("Also stored: \(model.name), \(Self.size(of: model))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let pending = state.modelSwitch {
                ModelSwitchView(state: state, pending: pending)
            }
        }
    }

    @ViewBuilder private var current: some View {
        let name = state.model.name
        let size = Self.size(of: state.model)
        switch state.modelState {
        case .missing:
            HStack {
                Text("\(name), \(size) one-time download").font(.callout).foregroundStyle(.secondary)
                Button("Download") { state.startDownload() }
            }
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: fraction).frame(maxWidth: 240)
                    .accessibilityLabel("Downloading speech model")
                HStack(spacing: 12) {
                    Text("\(Int(fraction * 100)) % of \(size)").font(.callout).monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Cancel") { state.cancelDownload() }.controlSize(.small)
                }
            }
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading \(name) …").font(.callout).foregroundStyle(.secondary)
            }
        case .installed:
            HStack {
                Text("\(name), \(size) on this Mac.").font(.callout).foregroundStyle(.secondary)
                if state.engineChoice == .parakeet {
                    Button("Activate") { state.startDownload() }
                }
            }
        case .resting:
            Text("\(name) is resting to free up memory and loads again with your next dictation.")
                .font(.callout).foregroundStyle(.secondary)
        case .ready:
            Text("\(name) is ready, \(size) on this Mac.").font(.callout).foregroundStyle(.secondary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.callout).foregroundStyle(.red)
                Button("Try Again") { state.startDownload() }
            }
        }
    }

    static func size(of model: SpeechModel) -> String {
        ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
    }
}

/// The model on its way in; the current one keeps working meanwhile.
private struct ModelSwitchView: View {
    let state: AppState
    let pending: ModelSwitch

    var body: some View {
        let name = pending.model.name
        let size = ModelStatusView.size(of: pending.model)
        switch pending.phase {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 8) {
                Text("Switching to \(name). Until then you keep dictating with \(state.model.name).")
                    .font(.callout).foregroundStyle(.secondary)
                ProgressView(value: fraction).frame(maxWidth: 240)
                    .accessibilityLabel("Downloading \(name)")
                HStack(spacing: 12) {
                    Text("\(Int(fraction * 100)) % of \(size)").font(.callout).monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Cancel") { state.cancelModelSwitch() }.controlSize(.small)
                }
            }
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading \(name) …").font(.callout).foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text("Switching to \(name) failed: \(message)").font(.callout).foregroundStyle(.red)
                HStack {
                    Button("Try Again") { state.retryModelSwitch() }
                    Button("Cancel") { state.cancelModelSwitch() }
                }
            }
        }
    }
}
