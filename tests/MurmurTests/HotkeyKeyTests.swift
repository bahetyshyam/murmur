import AppKit
@testable import Murmur

enum HotkeyKeyTests {
    static func run() {
        Harness.suite("HotkeyKey") {
            Harness.test("rightOptionParses") {
                let k = HotkeyKey.parse("alt_r")
                Harness.expectEqual(k.keycode, 61)
                Harness.expectEqual(k.displayName, "Right Option")
            }

            Harness.test("leftOptionParsesBothNames") {
                Harness.expectEqual(HotkeyKey.parse("alt_l").keycode, 58)
                Harness.expectEqual(HotkeyKey.parse("option_l").keycode, 58)
            }

            Harness.test("commandAndControlKeys") {
                Harness.expectEqual(HotkeyKey.parse("cmd_r").keycode, 54)
                Harness.expectEqual(HotkeyKey.parse("cmd_l").keycode, 55)
                Harness.expectEqual(HotkeyKey.parse("ctrl_r").keycode, 62)
                Harness.expectEqual(HotkeyKey.parse("ctrl_l").keycode, 59)
            }

            Harness.test("shiftKeys") {
                Harness.expectEqual(HotkeyKey.parse("shift_r").keycode, 60)
                Harness.expectEqual(HotkeyKey.parse("shift_l").keycode, 56)
            }

            Harness.test("caseInsensitive") {
                Harness.expectEqual(HotkeyKey.parse("ALT_R").keycode, 61)
                Harness.expectEqual(HotkeyKey.parse("Cmd_L").keycode, 55)
            }

            Harness.test("unknownFallsBackToDefault") {
                let k = HotkeyKey.parse("banana")
                Harness.expectEqual(k.keycode, HotkeyKey.defaultKey.keycode)
                Harness.expectEqual(k.displayName, HotkeyKey.defaultKey.displayName)
            }

            Harness.test("emptyFallsBackToDefault") {
                Harness.expectEqual(HotkeyKey.parse("").keycode, HotkeyKey.defaultKey.keycode)
            }

            Harness.test("defaultIsOptionBacktickChord") {
                let k = HotkeyKey.defaultKey
                Harness.expectEqual(k.keycode, 50)
                guard case .chord(_, let mods, _) = k else {
                    Harness.expect(false,"defaultKey should be a chord")
                    return
                }
                Harness.expectEqual(mods, .option)
            }

            Harness.test("chordParsesKeycodeAndModifiers") {
                let k = HotkeyKey.parse("chord:50:524288")
                Harness.expectEqual(k.keycode, 50)
                guard case .chord(_, let mods, _) = k else {
                    Harness.expect(false,"expected chord form"); return
                }
                Harness.expectEqual(mods, .option)
            }

            Harness.test("chordRoundTripsViaSerialized") {
                let original: HotkeyKey = .chord(
                    keycode: 46,
                    modifiers: [.control, .shift],
                    displayName: HotkeyKey.format(keycode: 46, modifiers: [.control, .shift])
                )
                let parsed = HotkeyKey.parse(original.serialized)
                Harness.expectEqual(parsed.keycode, 46)
                guard case .chord(_, let mods, _) = parsed else {
                    Harness.expect(false,"expected chord"); return
                }
                Harness.expectEqual(mods, [.control, .shift])
            }

            Harness.test("malformedChordFallsBackToDefault") {
                Harness.expectEqual(HotkeyKey.parse("chord:abc:xyz").keycode, HotkeyKey.defaultKey.keycode)
                Harness.expectEqual(HotkeyKey.parse("chord:50").keycode, HotkeyKey.defaultKey.keycode)
            }

            Harness.test("formatProducesExpectedSymbols") {
                Harness.expectEqual(HotkeyKey.format(keycode: 50, modifiers: .option), "⌥`")
                Harness.expectEqual(HotkeyKey.format(keycode: 46, modifiers: [.control, .shift]), "⌃⇧m")
                Harness.expectEqual(HotkeyKey.format(keycode: 49, modifiers: [.control, .option]), "⌃⌥Space")
            }

            Harness.test("legacyModifierSerializesToAlias") {
                let k: HotkeyKey = .modifier(keycode: 61, displayName: "Right Option")
                Harness.expectEqual(k.serialized, "alt_r")
            }
        }
    }
}
