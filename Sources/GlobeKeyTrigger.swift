import AppKit

/// The 🌐/fn key on its own as the trigger:
/// - hold it to dictate, let go to insert
/// - tap it twice to dictate hands-free, tap once more to finish
/// - fn together with any other key (fn+F1, fn+←) is normal fn use: nothing
///   starts, or a recording that already started is dropped.
///
/// Watching modifier keys of other apps needs the Accessibility permission
/// Inlaut already has for pasting. The key-down monitor that spots fn+key
/// only runs while fn is held.
@MainActor
final class GlobeKeyTrigger {
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}
    var onCancel: () -> Void = {}

    /// Held this long without another key, it counts as dictation; let go
    /// earlier, it was a tap.
    private let holdDelay: Duration = .milliseconds(200)
    /// Second tap must follow the first within this window.
    private let doubleTapWindow: TimeInterval = 0.4

    private enum Phase { case idle, pressed, holding, handsFree, interrupted }
    private var phase = Phase.idle
    private var lastTapAt = Date.distantPast
    private var ignoreNextRelease = false
    private var holdTask: Task<Void, Never>?
    private var flagsMonitors: [Any] = []
    private var keyMonitors: [Any] = []

    func start() {
        guard flagsMonitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.flagsChanged(event) }
        }
        flagsMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler),
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { handler($0); return $0 },
        ].compactMap { $0 }
    }

    func stop() {
        (flagsMonitors + keyMonitors).forEach(NSEvent.removeMonitor)
        flagsMonitors = []
        keyMonitors = []
        holdTask?.cancel()
        if phase == .holding || phase == .handsFree { onCancel() }
        phase = .idle
    }

    private func flagsChanged(_ event: NSEvent) {
        let globeDown = event.modifierFlags.contains(.function)
        if event.keyCode == 63 {  // the 🌐/fn key itself
            globeDown ? pressed() : released()
        } else if phase == .pressed || phase == .holding {
            otherKey()  // another modifier joined, e.g. fn+⇧
        }
    }

    private func pressed() {
        watchOtherKeys(true)
        switch phase {
        case .handsFree:
            // One tap finishes a hands-free dictation.
            phase = .idle
            ignoreNextRelease = true
            onStop()
            return
        case .idle where Date().timeIntervalSince(lastTapAt) < doubleTapWindow:
            phase = .handsFree
            ignoreNextRelease = true
            lastTapAt = .distantPast
            onStart()
            return
        default:
            break
        }
        phase = .pressed
        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(for: holdDelay)
            guard !Task.isCancelled, phase == .pressed else { return }
            phase = .holding
            onStart()
        }
    }

    private func released() {
        watchOtherKeys(false)
        holdTask?.cancel()
        if ignoreNextRelease {
            ignoreNextRelease = false
            return
        }
        switch phase {
        case .holding:
            phase = .idle
            onStop()
        case .pressed:
            phase = .idle
            lastTapAt = Date()
        case .interrupted:
            phase = .idle
        case .idle, .handsFree:
            break
        }
    }

    private func otherKey() {
        holdTask?.cancel()
        if phase == .holding { onCancel() }
        if phase == .pressed || phase == .holding { phase = .interrupted }
        lastTapAt = .distantPast
    }

    private func watchOtherKeys(_ on: Bool) {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors = []
        guard on else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .pressed || self.phase == .holding else { return }
                self.otherKey()
            }
        }
        keyMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler),
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { handler($0); return $0 },
        ].compactMap { $0 }
    }
}
