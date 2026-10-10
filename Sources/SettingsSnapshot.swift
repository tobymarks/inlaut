#if DEBUG
import AppKit
import SwiftUI

/// Website screenshots: `-renderSettings /path.png` renders the real
/// SettingsView offscreen once the model is ready and quits. Combine with
/// `-AppleLanguages '(en)' -AppleLocale en_US -language english` for the
/// English one; launch arguments do not change the stored settings.
@MainActor
enum SettingsSnapshot {
    static func renderIfRequested(state: AppState) {
        guard let path = UserDefaults.standard.string(forKey: "renderSettings") else { return }
        Task {
            for _ in 0..<240 where state.modelState != .ready { try? await Task.sleep(for: .milliseconds(500)) }
            // Controls only show the accent colour in the key window of the active app.
            NSApp.setActivationPolicy(.regular)
            let host = NSHostingView(rootView: SettingsView(state: state))
            host.frame = NSRect(x: 0, y: 0, width: 560, height: 740)
            let window = KeyWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(2))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}
#endif
