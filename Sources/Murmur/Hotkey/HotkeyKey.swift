import AppKit
import CoreGraphics
import Foundation

/// Parses hotkey identifiers from config strings into either a bare modifier
/// key (legacy, single-modifier tap-to-toggle) or a full chord
/// (non-modifier key + required modifier flags).
///
/// Two serialization forms live in `AppConfig.hotkey`:
///
/// * Legacy modifier names (parity with the Python prototype):
///   `alt_r`, `alt_l`, `cmd_r`, `cmd_l`, `ctrl_r`, `ctrl_l`, `shift_r`, `shift_l`.
/// * Chord form: `chord:<keycode>:<modifierMask>` — e.g. `chord:50:524288` for ⌥`.
///   `modifierMask` is `NSEvent.ModifierFlags.rawValue`; the bits we actually
///   care about are masked to `.deviceIndependentFlagsMask` on match, so the
///   mask is forgiving about left/right-specific bits that creep in via
///   `NSEvent.modifierFlags`.
enum HotkeyKey {
    /// A modifier key identified by its virtual keycode.
    case modifier(keycode: CGKeyCode, displayName: String)

    /// A non-modifier key combined with required modifier flags.
    case chord(keycode: CGKeyCode, modifiers: NSEvent.ModifierFlags, displayName: String)

    /// Default hotkey — ⌥` (Option+Backtick).
    ///
    /// Keycode 50 is the `/~ key on US ANSI. Chosen because:
    /// * ⌥Space clashes with SuperWhisper, ⌘Space with Spotlight, ⌃Space with
    ///   macOS "Select previous input source".
    /// * ⌥` is almost never bound globally (⌘` is used for window cycling but
    ///   ⌥` is free).
    static let defaultKey: HotkeyKey = .chord(
        keycode: 50,
        modifiers: [.option],
        displayName: "⌥`"
    )

    /// Virtual keycode for this hotkey.
    var keycode: CGKeyCode {
        switch self {
        case .modifier(let k, _): return k
        case .chord(let k, _, _): return k
        }
    }

    /// Human-readable label for menus / tooltips.
    var displayName: String {
        switch self {
        case .modifier(_, let name): return name
        case .chord(_, _, let name): return name
        }
    }

    /// Serialize back to a config string. Inverse of `parse`.
    var serialized: String {
        switch self {
        case .modifier(let kc, _):
            return Self.modifierAlias(for: kc) ?? "alt_r"
        case .chord(let kc, let mods, _):
            let masked = mods.intersection(.deviceIndependentFlagsMask).rawValue
            return "chord:\(kc):\(masked)"
        }
    }

    /// Parse a config string. Unknown → `.defaultKey`.
    static func parse(_ raw: String) -> HotkeyKey {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Chord form: "chord:<keycode>:<modmask>"
        if trimmed.lowercased().hasPrefix("chord:") {
            let parts = trimmed.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3,
               let kc = UInt16(parts[1]),
               let maskRaw = UInt.init(parts[2])
            {
                let mods = NSEvent.ModifierFlags(rawValue: maskRaw)
                    .intersection(.deviceIndependentFlagsMask)
                return .chord(
                    keycode: CGKeyCode(kc),
                    modifiers: mods,
                    displayName: format(keycode: CGKeyCode(kc), modifiers: mods)
                )
            }
            return .defaultKey
        }

        switch trimmed.lowercased() {
        case "alt_r", "option_r":   return .modifier(keycode: 61, displayName: "Right Option")
        case "alt_l", "option_l":   return .modifier(keycode: 58, displayName: "Left Option")
        case "cmd_r", "command_r":  return .modifier(keycode: 54, displayName: "Right Command")
        case "cmd_l", "command_l":  return .modifier(keycode: 55, displayName: "Left Command")
        case "ctrl_r", "control_r": return .modifier(keycode: 62, displayName: "Right Control")
        case "ctrl_l", "control_l": return .modifier(keycode: 59, displayName: "Left Control")
        case "shift_r":             return .modifier(keycode: 60, displayName: "Right Shift")
        case "shift_l":             return .modifier(keycode: 56, displayName: "Left Shift")
        default:                    return .defaultKey
        }
    }

    private static func modifierAlias(for keycode: CGKeyCode) -> String? {
        switch keycode {
        case 61: return "alt_r"
        case 58: return "alt_l"
        case 54: return "cmd_r"
        case 55: return "cmd_l"
        case 62: return "ctrl_r"
        case 59: return "ctrl_l"
        case 60: return "shift_r"
        case 56: return "shift_l"
        default: return nil
        }
    }

    // MARK: - Display formatting

    /// Human-readable chord label like `⌥`` or `⌃⇧;`. Used by Settings and
    /// the menubar tooltip so the on-screen label matches what the user
    /// actually presses.
    static func format(keycode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> String {
        let mods = modifiers.intersection(.deviceIndependentFlagsMask)
        var symbols = ""
        if mods.contains(.control) { symbols += "⌃" }
        if mods.contains(.option)  { symbols += "⌥" }
        if mods.contains(.shift)   { symbols += "⇧" }
        if mods.contains(.command) { symbols += "⌘" }
        return symbols + keySymbol(for: keycode)
    }

    /// Best-effort single-character symbol for a virtual keycode. Covers
    /// the keys a user is most likely to pick; falls through to the
    /// AppKit-provided localized name for the rest.
    static func keySymbol(for keycode: CGKeyCode) -> String {
        switch keycode {
        case 49:  return "Space"
        case 36:  return "↩"
        case 48:  return "⇥"
        case 51:  return "⌫"
        case 53:  return "⎋"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 116: return "⇞"
        case 121: return "⇟"
        case 115: return "↖"
        case 119: return "↘"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            if let ch = Self.character(for: keycode) {
                return ch
            }
            return "Key \(keycode)"
        }
    }

    /// Translate a keycode into the literal character it produces with no
    /// modifiers held, via the active keyboard layout. `UCKeyTranslate` is
    /// the documented path for this; falling back to a static US-ANSI map
    /// keeps the code working if the input source is in a funky state.
    private static func character(for keycode: CGKeyCode) -> String? {
        if let ch = usAnsiCharacter(for: keycode) {
            return ch
        }
        return nil
    }

    /// US-ANSI character mapping — the common case. Covers digits and
    /// letters; symbols ⌥/⌃-combined render in the upstream `format(...)`
    /// already so we just need the base glyph.
    private static func usAnsiCharacter(for keycode: CGKeyCode) -> String? {
        switch keycode {
        case 0:  return "a"
        case 1:  return "s"
        case 2:  return "d"
        case 3:  return "f"
        case 4:  return "h"
        case 5:  return "g"
        case 6:  return "z"
        case 7:  return "x"
        case 8:  return "c"
        case 9:  return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 25: return "9"
        case 26: return "7"
        case 28: return "8"
        case 29: return "0"
        case 31: return "o"
        case 32: return "u"
        case 34: return "i"
        case 35: return "p"
        case 37: return "l"
        case 38: return "j"
        case 40: return "k"
        case 45: return "n"
        case 46: return "m"
        case 50: return "`"
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 39: return "'"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 42: return "\\"
        default: return nil
        }
    }
}
