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
            return .commonApp(String(localized: "⌥Space is often taken by Raycast, Alfred or ChatGPT."))
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
        return name(for: shortcut) ?? defaultNames[Combo(shortcut)].map { String(localized: "“\($0)”") } ?? String(localized: "a system shortcut")
    }

    private struct Combo: Hashable {
        let key: Int, mods: Int
        init(_ key: Int, _ mods: Int) { self.key = key; self.mods = mods }
        init(_ s: Shortcut) { key = Int(s.keyCode); mods = Int(s.modifiers) }
    }

    /// Shortcuts the user never changed are missing from the preferences
    /// file, so their factory keys are matched here.
    private static let defaultNames: [Combo: String] = [
        Combo(kVK_Space, cmdKey): String(localized: "Spotlight"),
        Combo(kVK_Space, cmdKey | optionKey): String(localized: "Finder search window"),
        Combo(kVK_Space, controlKey): String(localized: "Previous input source"),
        Combo(kVK_Space, controlKey | optionKey): String(localized: "Next input source"),
        Combo(kVK_ANSI_3, cmdKey | shiftKey): String(localized: "Save screenshot"),
        Combo(kVK_ANSI_3, cmdKey | shiftKey | controlKey): String(localized: "Copy screenshot"),
        Combo(kVK_ANSI_4, cmdKey | shiftKey): String(localized: "Save area as picture"),
        Combo(kVK_ANSI_4, cmdKey | shiftKey | controlKey): String(localized: "Copy area"),
        Combo(kVK_ANSI_5, cmdKey | shiftKey): String(localized: "Screenshot options"),
        Combo(kVK_UpArrow, controlKey): String(localized: "Mission Control"),
        Combo(kVK_DownArrow, controlKey): String(localized: "Application windows"),
        Combo(kVK_LeftArrow, controlKey): String(localized: "Move left a space"),
        Combo(kVK_RightArrow, controlKey): String(localized: "Move right a space"),
        Combo(kVK_ANSI_D, cmdKey | optionKey): String(localized: "Show/hide Dock"),
        Combo(kVK_ANSI_Grave, cmdKey): String(localized: "Next window"),
        Combo(kVK_F11, 0): String(localized: "Show desktop"),
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
        27: String(localized: "Next window"), 28: String(localized: "Save screenshot"), 29: String(localized: "Copy screenshot"),
        30: String(localized: "Save area as picture"), 31: String(localized: "Copy area"), 32: String(localized: "Mission Control"),
        33: String(localized: "Application windows"), 36: String(localized: "Show desktop"), 52: String(localized: "Show/hide Dock"),
        60: String(localized: "Previous input source"), 61: String(localized: "Next input source"), 64: String(localized: "Spotlight"),
        65: String(localized: "Finder search window"), 79: String(localized: "Move left a space"), 81: String(localized: "Move right a space"),
        160: String(localized: "Launchpad"), 163: String(localized: "Notification Center"), 175: String(localized: "Do Not Disturb"),
        184: String(localized: "Screenshot options"),
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
        case 1: String(localized: "change the input source")
        case 2: String(localized: "show Emoji & Symbols")
        case 3: String(localized: "start macOS Dictation")
        default: String(localized: "perform a system action")
        }
    }

    static func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}
