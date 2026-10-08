import AppKit
import ApplicationServices
import SwiftUI

/// A small floating pill next to the text cursor, so you can see that
/// Inlaut is listening even in full screen where the menu bar is hidden.
/// It only exists during a dictation; nothing runs between dictations.
@MainActor
final class RecordingIndicator {
    private var panel: NSPanel?
    private let model = IndicatorModel()
    private var levelTimer: Timer?
    private var hideTask: Task<Void, Never>?

    func showRecording(level: @escaping @MainActor () -> Float) {
        hideTask?.cancel()
        model.phase = .recording
        model.levels = Array(repeating: 0, count: IndicatorModel.barCount)
        present()
        // ~20 updates per second, and only while recording.
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [model] _ in
            MainActor.assumeIsolated { model.push(level()) }
        }
    }

    func showTranscribing() {
        stopLevels()
        model.phase = .transcribing
    }

    func showMessage(_ text: String) {
        stopLevels()
        model.phase = .message(text)
        present(reposition: panel == nil)
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { hide() }
        }
    }

    func hide() {
        stopLevels()
        hideTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    private func stopLevels() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func present(reposition: Bool = true) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if reposition { place(panel) }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: IndicatorView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }

    /// Just below the text cursor if the focused app reports it, else below
    /// the focused element, else bottom centre of the screen with the mouse.
    private func place(_ panel: NSPanel) {
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 120, height: 32))
        let size = panel.frame.size
        let anchor = Self.caretRect() ?? Self.focusedElementRect()
        let screen = anchor.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame ?? screen?.frame else { return }

        var origin: NSPoint
        if let anchor {
            origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 6)
            if origin.y < visible.minY { origin.y = anchor.maxY + 6 }  // no room below: go above
        } else {
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 80)
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Accessibility lookups (Cocoa coordinates, bottom-left origin)

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        // A hung app must not freeze the indicator.
        AXUIElementSetMessagingTimeout(system, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func caretRect() -> NSRect? {
        guard let element = focusedElement() else { return nil }
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }
        return toCocoa(rect)
    }

    private static func focusedElementRect() -> NSRect? {
        guard let element = focusedElement() else { return nil }
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }
        // Big elements (a whole editor) are a poor anchor: use their bottom edge.
        let rect = CGRect(origin: point, size: size)
        let cocoa = toCocoa(rect)
        return size.height > 120 ? NSRect(x: cocoa.minX + 12, y: cocoa.minY + 40, width: 1, height: 1) : cocoa
    }

    /// AX uses a top-left origin on the primary screen; AppKit bottom-left.
    private static func toCocoa(_ rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

@MainActor
@Observable
final class IndicatorModel {
    enum Phase: Equatable { case recording, transcribing, message(String) }
    static let barCount = 7

    var phase: Phase = .recording
    var levels: [Float] = Array(repeating: 0, count: barCount)

    /// Peak 0…1 from the mic; speech peaks sit far below 1, so scale up.
    func push(_ level: Float) {
        let scaled = min(1, sqrt(level) * 1.6)
        levels.removeFirst()
        levels.append(scaled)
    }
}

private struct IndicatorView: View {
    let model: IndicatorModel

    var body: some View {
        HStack(spacing: 8) {
            switch model.phase {
            case .recording:
                Circle().fill(.red).frame(width: 8, height: 8)
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(model.levels.indices, id: \.self) { i in
                        Capsule()
                            .fill(.primary.opacity(0.85))
                            .frame(width: 3, height: 4 + CGFloat(model.levels[i]) * 14)
                    }
                }
                .frame(height: 18)
                .animation(.easeOut(duration: 0.08), value: model.levels)
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Erkennt …").font(.callout)
            case .message(let text):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(text).font(.callout).lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .fixedSize()
        .glassEffect(.regular, in: .capsule)
    }
}
