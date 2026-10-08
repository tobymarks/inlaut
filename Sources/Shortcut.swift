import AppKit
import Carbon.HIToolbox

/// A global key combination, stored in Carbon terms because that is what
/// RegisterEventHotKey takes. Carbon hot keys need no Accessibility or Input
/// Monitoring permission and work inside the App Store sandbox.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon mask: cmdKey, optionKey, controlKey, shiftKey
    var keyName: String

    // ⌃⌥Space would collide with "next input source", enabled by default.
    static let `default` = Shortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey | shiftKey),
        keyName: "Space"
    )

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName
    }

    /// nil when the event is not a usable shortcut: plain letters without a
    /// modifier would swallow normal typing system-wide.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        let code = Int(event.keyCode)
        let fKey = Self.functionKeys[code]
        if mods == 0 && fKey == nil { return nil }
        if mods == UInt32(shiftKey) && fKey == nil { return nil }
        self.keyCode = UInt32(code)
        self.modifiers = mods
        self.keyName = fKey ?? Self.specialKeys[code]
            ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
    }

    init(keyCode: UInt32, modifiers: UInt32, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
    ]
}

/// One registered Carbon hot key with press and release callbacks.
@MainActor
final class HotKey {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isDown = false

    init() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            let kind = GetEventKind(event)
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { hotKey.handle(pressed: kind == UInt32(kEventHotKeyPressed)) }
            return noErr
        }, specs.count, &specs, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func register(_ shortcut: Shortcut) {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x4454_4154), id: 1)  // "DTAT"
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        isDown = false
    }

    private func handle(pressed: Bool) {
        // Key repeat would otherwise restart the recording while it is held.
        guard pressed != isDown else { return }
        isDown = pressed
        pressed ? onPress() : onRelease()
    }
}
