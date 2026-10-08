import AppKit
import ApplicationServices
import SwiftUI

enum IndicatorPosition: String, CaseIterable, Identifiable {
    case bottomCenter, caret
    var id: String { rawValue }
    var label: String { self == .bottomCenter ? "Unten mittig" : "Am Textcursor" }
}

/// A small floating pill, so you can see that inlaut is listening even in
/// full screen where the menu bar is hidden. It only exists during a
/// dictation; nothing runs between dictations.
@MainActor
final class RecordingIndicator {
    var position: IndicatorPosition = .bottomCenter
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
        guard let panel else { return }
        self.panel = nil
        // Fade out (design guide: 120 ms, ease-in), then take it off screen.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.reduceMotion ? 0 : 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            panel.orderOut(nil)
        }
    }

    private func stopLevels() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func present(reposition: Bool = true) {
        let isNew = self.panel == nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if reposition { place(panel) }
        guard isNew else { return }
        // Fade in (design guide: 160 ms, ease-out); instant with Reduce Motion.
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.reduceMotion ? 0 : 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

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

    /// Bottom centre of the screen you work on, or just below the text
    /// cursor when that is chosen and the focused app reports it. Many apps
    /// (Chromium, Electron) report no usable caret; they get bottom centre.
    private func place(_ panel: NSPanel) {
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 120, height: 32))
        let size = panel.frame.size
        let field = Self.focusedElementRect()
        let caret = position == .caret ? Self.caretRect() : nil
        let screen = (caret ?? field).flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame

        var origin: NSPoint
        if let caret {
            origin = NSPoint(x: caret.minX, y: caret.minY - size.height - 6)
            if origin.y < visible.minY { origin.y = caret.maxY + 6 }  // no room below: go above
        } else {
            // Use the physical display edge, including the area occupied by
            // the Dock. The non-interactive panel does not intercept clicks.
            panel.setFrameOrigin(Self.bottomOrigin(size: size, screenFrame: screen.frame))
            return
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    static func bottomOrigin(size: NSSize, screenFrame: NSRect) -> NSPoint {
        NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.minY + 12)
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
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        // Chromium answers an empty range (a plain blinking cursor) with junk;
        // the character before the cursor gives a reliable box to stand on.
        if range.length == 0, range.location > 0,
           let before = bounds(of: CFRange(location: range.location - 1, length: 1), in: element) {
            return NSRect(x: before.maxX, y: before.minY, width: 1, height: before.height)
        }
        return bounds(of: range, in: element)
    }

    private static func bounds(of range: CFRange, in element: AXUIElement) -> NSRect? {
        var range = range
        guard let axRange = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.height > 0, rect.height < 200, rect.origin != .zero else { return nil }
        let cocoa = toCocoa(rect)
        return NSScreen.screens.contains { $0.frame.intersects(cocoa) } ? cocoa : nil
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
        return toCocoa(CGRect(origin: point, size: size))
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

    /// Peak 0…1 from the mic, about every 50 ms. Speech peaks sit far below 1,
    /// so scale up; then smooth so the bars rise fast (~70 ms) and fall
    /// slowly (~160 ms), as the design guide asks.
    func push(_ level: Float) {
        let target = min(1, sqrt(level) * 1.6)
        let previous = levels.last ?? 0
        let smoothing: Float = target > previous ? 0.51 : 0.27
        levels.removeFirst()
        levels.append(previous + (target - previous) * smoothing)
    }
}

/// Native glass and the Sprachimpuls palette, with opaque accessibility fallbacks.
private struct IndicatorView: View {
    let model: IndicatorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    /// Static bars shown instead of live levels with Reduce Motion.
    private static let restingHeights: [CGFloat] = [4, 7, 11, 14, 11, 7, 4]

    var body: some View {
        let pill = content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.inlautInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 38)
            .fixedSize()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: model.phase)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        // Glass needs something legible behind it; with Reduce Transparency
        // or Increase Contrast the pill gets an opaque system background.
        if reduceTransparency || contrast == .increased {
            pill
                .background(Capsule().fill(Color.inlautSurface))
                .overlay(Capsule().strokeBorder(Color.inlautInk.opacity(contrast == .increased ? 0.6 : 0.2)))
        } else {
            pill.glassEffect(.regular, in: .capsule)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .recording:
            HStack(spacing: 10) {
                Circle().fill(Color.inlautRecording).frame(width: 6, height: 6)
                Text("Hört zu")
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(model.levels.indices, id: \.self) { i in
                        Capsule()
                            .fill(Color.inlautBrand)
                            .frame(width: 3, height: reduceMotion
                                ? Self.restingHeights[i]
                                : 4 + CGFloat(model.levels[i]) * 14)
                    }
                }
                .frame(height: 18)
                .animation(reduceMotion ? nil : .linear(duration: 0.05), value: model.levels)
            }
            .transition(.opacity)
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Erkennt …")
            }
            .frame(minWidth: 112)
            .transition(.opacity)
        case .message(let text):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(text).lineLimit(2)
            }
            .transition(.opacity)
        }
    }

    private var accessibilityText: String {
        switch model.phase {
        case .recording: "inlaut nimmt auf"
        case .transcribing: "inlaut erkennt"
        case .message(let text): text
        }
    }
}
