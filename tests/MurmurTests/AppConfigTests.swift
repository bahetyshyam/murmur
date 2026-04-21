import Foundation
@testable import Murmur

@MainActor
enum AppConfigTests {
    static func run() {
        Harness.suite("AppConfig") {
            Harness.test("defaultsWhenEmpty") {
                let (suite, defaults) = makeScopedDefaults()
                defer { defaults.removePersistentDomain(forName: suite) }

                let cfg = AppConfig(defaults: defaults)
                Harness.expectEqual(cfg.hotkey, "chord:50:524288")
                Harness.expectEqual(cfg.model, "gpt-4o-transcribe")
                Harness.expectEqual(cfg.biasingPrompt, "")
                Harness.expectEqual(cfg.language, "")
                Harness.expectEqual(cfg.sampleRate, 16000)
                Harness.expectEqual(cfg.channels, 1)
                Harness.expectEqual(cfg.minPressDurationS, 0.3)
                Harness.expectEqual(cfg.releaseTailMs, 300)
                Harness.expectEqual(cfg.pasteAtCursor, true)
                Harness.expectEqual(cfg.restoreClipboard, true)
                Harness.expectEqual(cfg.chimesEnabled, true)
                Harness.expectEqual(cfg.hudEnabled, true)
                Harness.expectEqual(cfg.historyRetentionDays, 30)
            }

            Harness.test("mutationsPersist") {
                let (suite, defaults) = makeScopedDefaults()
                defer { defaults.removePersistentDomain(forName: suite) }

                let cfg = AppConfig(defaults: defaults)
                cfg.model = "whisper-1"
                cfg.biasingPrompt = "Postman, gRPC, OAuth"
                cfg.releaseTailMs = 450
                cfg.chimesEnabled = false

                // New instance over the same suite → reads the persisted values.
                let reloaded = AppConfig(defaults: defaults)
                Harness.expectEqual(reloaded.model, "whisper-1")
                Harness.expectEqual(reloaded.biasingPrompt, "Postman, gRPC, OAuth")
                Harness.expectEqual(reloaded.releaseTailMs, 450)
                Harness.expectEqual(reloaded.chimesEnabled, false)
            }

            Harness.test("boolFalseIsNotOverwrittenByDefault") {
                // Guard against a subtle bug: `defaults.bool(forKey:)` returns
                // false for missing keys, which would make "user disabled
                // chimes" and "never set" indistinguishable. The init uses
                // `object(forKey:) as? Bool`.
                let (suite, defaults) = makeScopedDefaults()
                defer { defaults.removePersistentDomain(forName: suite) }

                defaults.set(false, forKey: "chimesEnabled")
                let cfg = AppConfig(defaults: defaults)
                Harness.expectEqual(cfg.chimesEnabled, false)
            }
        }
    }

    private static func makeScopedDefaults() -> (String, UserDefaults) {
        let name = "MurmurTests.\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }
}
