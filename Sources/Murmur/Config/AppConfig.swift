import Foundation
import Observation

/// User-facing settings, persisted to UserDefaults. Mirrors the Python
/// config.yaml fields so migrating users keep the same knobs.
///
/// Why UserDefaults and not a YAML file?
/// - It's the native macOS idiom (Preferences pane observables, plist-backed).
/// - SwiftUI `@AppStorage` binds to it for free in the Settings scene.
/// - Survives app deletes/reinstalls less nicely than YAML, but for a small
///   personal tool that's fine — users can re-set their prefs in seconds.
@Observable
@MainActor
final class AppConfig {
    // MARK: Defaults

    /// Default hotkey: Right Option (`alt_r`). Modifier-only keys fire
    /// `.flagsChanged` events, which session-level CGEventTaps deliver
    /// reliably even for non-notarized (self-signed) apps on macOS 26 —
    /// unlike chord hotkeys (⌥`, ⌘⇧Space, …) whose `.keyDown` events get
    /// dropped. Right Option is also what freeflow / SuperWhisper ship
    /// with: single-tap, thumb-accessible, no conflict with the Fn key
    /// emoji-picker default.
    static let defaultHotkey = "alt_r"
    static let defaultModel = "gpt-4o-transcribe"

    // MARK: Stored properties (observed by SwiftUI + persisted on didSet)

    var hotkey: String { didSet { persist(\.hotkey, Keys.hotkey) } }
    var model: String { didSet { persist(\.model, Keys.model) } }
    var biasingPrompt: String { didSet { persist(\.biasingPrompt, Keys.biasingPrompt) } }
    var language: String { didSet { persist(\.language, Keys.language) } }
    var sampleRate: Int { didSet { persist(\.sampleRate, Keys.sampleRate) } }
    var channels: Int { didSet { persist(\.channels, Keys.channels) } }
    var minPressDurationS: Double { didSet { persist(\.minPressDurationS, Keys.minPressDurationS) } }
    var releaseTailMs: Int { didSet { persist(\.releaseTailMs, Keys.releaseTailMs) } }
    var pasteAtCursor: Bool { didSet { persist(\.pasteAtCursor, Keys.pasteAtCursor) } }
    var restoreClipboard: Bool { didSet { persist(\.restoreClipboard, Keys.restoreClipboard) } }
    var chimesEnabled: Bool { didSet { persist(\.chimesEnabled, Keys.chimesEnabled) } }
    var hudEnabled: Bool { didSet { persist(\.hudEnabled, Keys.hudEnabled) } }
    var historyRetentionDays: Int { didSet { persist(\.historyRetentionDays, Keys.historyRetentionDays) } }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Migration: older builds defaulted to a chord (`chord:50:524288` = ⌥`),
        // but chord hotkeys need notarization to work reliably on macOS 26. If
        // the persisted value is a chord form, silently promote to the new
        // modifier-only default so the user's hotkey keeps working after the
        // upgrade without them having to revisit Settings.
        let persistedHotkey = defaults.string(forKey: Keys.hotkey)
        if let raw = persistedHotkey, raw.lowercased().hasPrefix("chord:") {
            self.hotkey = Self.defaultHotkey
            defaults.set(Self.defaultHotkey, forKey: Keys.hotkey)
        } else {
            self.hotkey = persistedHotkey ?? Self.defaultHotkey
        }
        self.model = defaults.string(forKey: Keys.model) ?? Self.defaultModel
        self.biasingPrompt = defaults.string(forKey: Keys.biasingPrompt) ?? ""
        self.language = defaults.string(forKey: Keys.language) ?? ""
        self.sampleRate = (defaults.object(forKey: Keys.sampleRate) as? Int) ?? 16000
        self.channels = (defaults.object(forKey: Keys.channels) as? Int) ?? 1
        self.minPressDurationS = (defaults.object(forKey: Keys.minPressDurationS) as? Double) ?? 0.3
        self.releaseTailMs = (defaults.object(forKey: Keys.releaseTailMs) as? Int) ?? 300
        self.pasteAtCursor = (defaults.object(forKey: Keys.pasteAtCursor) as? Bool) ?? true
        self.restoreClipboard = (defaults.object(forKey: Keys.restoreClipboard) as? Bool) ?? true
        self.chimesEnabled = (defaults.object(forKey: Keys.chimesEnabled) as? Bool) ?? true
        self.hudEnabled = (defaults.object(forKey: Keys.hudEnabled) as? Bool) ?? true
        self.historyRetentionDays = (defaults.object(forKey: Keys.historyRetentionDays) as? Int) ?? 30
    }

    // MARK: Private

    private let defaults: UserDefaults

    private func persist<T>(_ keyPath: KeyPath<AppConfig, T>, _ key: String) {
        defaults.set(self[keyPath: keyPath], forKey: key)
    }

    private enum Keys {
        static let hotkey = "hotkey"
        static let model = "model"
        static let biasingPrompt = "biasingPrompt"
        static let language = "language"
        static let sampleRate = "sampleRate"
        static let channels = "channels"
        static let minPressDurationS = "minPressDurationS"
        static let releaseTailMs = "releaseTailMs"
        static let pasteAtCursor = "pasteAtCursor"
        static let restoreClipboard = "restoreClipboard"
        static let chimesEnabled = "chimesEnabled"
        static let hudEnabled = "hudEnabled"
        static let historyRetentionDays = "historyRetentionDays"
    }
}
