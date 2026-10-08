import AppKit
import Carbon.HIToolbox

/// What can be checked about a shortcut before using it. macOS does not tell
/// one app about another app's global hot keys (RegisterEventHotKey succeeds
/// for duplicates, even with kEventHotKeyExclusive), so only the system's own
/// shortcuts can be checked for real; a few well-known app defaults get a hint.
enum ShortcutConflicts {
    enum Finding: Equatable {
        case system(String)    // enabled macOS shortcut — will not work reliably
        case commonApp(String) // often taken by other tools — just a hint
    }

    static func check(_ shortcut: Shortcut) -> Finding? {
        if let name = systemShortcut(matching: shortcut) { return .system(name) }
        if shortcut.keyCode == UInt32(kVK_Space), shortcut.modifiers == UInt32(optionKey) {
            return .commonApp("⌥Space ist oft von Raycast, Alfred oder ChatGPT belegt.")
        }
        return nil
    }

    /// Name of an enabled macOS shortcut with the same keys, or nil.
    private static func systemShortcut(matching shortcut: Shortcut) -> String? {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
              let entries = array?.takeRetainedValue() as? [[String: Any]] else { return nil }
        // Only the four modifiers we register with take part in the match.
        let relevant = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let taken = entries.contains { entry in
            (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true
                && (entry[kHISymbolicHotKeyCode as String] as? Int).map(UInt32.init) == shortcut.keyCode
                && (entry[kHISymbolicHotKeyModifiers as String] as? Int).map { UInt32($0) & relevant } == shortcut.modifiers
        }
        guard taken else { return nil }
        return name(for: shortcut) ?? defaultNames[Combo(shortcut)].map { "„\($0)“" } ?? "einen Systemkurzbefehl"
    }

    private struct Combo: Hashable {
        let key: Int, mods: Int
        init(_ key: Int, _ mods: Int) { self.key = key; self.mods = mods }
        init(_ s: Shortcut) { key = Int(s.keyCode); mods = Int(s.modifiers) }
    }

    /// Shortcuts the user never changed are missing from the preferences
    /// file, so their factory keys are matched here.
    private static let defaultNames: [Combo: String] = [
        Combo(kVK_Space, cmdKey): "Spotlight",
        Combo(kVK_Space, cmdKey | optionKey): "Finder-Suchfenster",
        Combo(kVK_Space, controlKey): "Vorherige Eingabequelle",
        Combo(kVK_Space, controlKey | optionKey): "Nächste Eingabequelle",
        Combo(kVK_ANSI_3, cmdKey | shiftKey): "Bildschirmfoto sichern",
        Combo(kVK_ANSI_3, cmdKey | shiftKey | controlKey): "Bildschirmfoto kopieren",
        Combo(kVK_ANSI_4, cmdKey | shiftKey): "Bereich als Bild sichern",
        Combo(kVK_ANSI_4, cmdKey | shiftKey | controlKey): "Bereich kopieren",
        Combo(kVK_ANSI_5, cmdKey | shiftKey): "Bildschirmfoto-Optionen",
        Combo(kVK_UpArrow, controlKey): "Mission Control",
        Combo(kVK_DownArrow, controlKey): "Programmfenster",
        Combo(kVK_LeftArrow, controlKey): "Space nach links",
        Combo(kVK_RightArrow, controlKey): "Space nach rechts",
        Combo(kVK_ANSI_D, cmdKey | optionKey): "Dock ein-/ausblenden",
        Combo(kVK_ANSI_Grave, cmdKey): "Nächstes Fenster",
        Combo(kVK_F11, 0): "Schreibtisch anzeigen",
    ]

    /// The symbolic hot key list has no names; the preferences file has IDs
    /// for the shortcuts it stores, which map to the names in System Settings.
    private static func name(for shortcut: Shortcut) -> String? {
        guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") as? [String: [String: Any]] else { return nil }
        let cocoa = cocoaModifiers(shortcut.modifiers)
        for (id, entry) in all {
            guard let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int], parameters.count == 3,
                  UInt32(parameters[1]) == shortcut.keyCode,
                  UInt(parameters[2]) & 0x1E0000 == cocoa else { continue }
            if let known = Int(id).flatMap({ names[$0] }) { return "„\(known)“" }
        }
        return nil
    }

    private static func cocoaModifiers(_ carbon: UInt32) -> UInt {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags.rawValue
    }

    private static let names: [Int: String] = [
        27: "Nächstes Fenster", 28: "Bildschirmfoto sichern", 29: "Bildschirmfoto kopieren",
        30: "Bereich als Bild sichern", 31: "Bereich kopieren", 32: "Mission Control",
        33: "Programmfenster", 36: "Schreibtisch anzeigen", 52: "Dock ein-/ausblenden",
        60: "Vorherige Eingabequelle", 61: "Nächste Eingabequelle", 64: "Spotlight",
        65: "Finder-Suchfenster", 79: "Space nach links", 81: "Space nach rechts",
        160: "Launchpad", 163: "Mitteilungszentrale", 175: "Nicht stören",
        184: "Bildschirmfoto-Optionen",
    ]
}

/// The system action of the 🌐 key (System Settings → Keyboard).
enum GlobeKeySetting {
    /// 0 do nothing, 1 change input source, 2 emoji & symbols, 3 start dictation.
    static var action: Int {
        (CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? Int) ?? 2
    }

    static var conflicts: Bool { action != 0 }

    static var actionName: String {
        switch action {
        case 1: "die Eingabequelle wechseln"
        case 2: "Emoji & Symbole zeigen"
        case 3: "die Diktierfunktion von macOS starten"
        default: "eine Systemaktion ausführen"
        }
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}
