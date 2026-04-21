import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

/// Global tap-to-toggle hotkey via a `CGEventTap`.
///
/// Fires `onToggle` on the main actor when the user's configured hotkey is
/// pressed. The downstream state machine flips idle ↔ recording on each
/// toggle — no hold, no release pairing.
///
/// Why CGEventTap and not `NSEvent.addGlobalMonitor`:
///   * `NSEvent` global monitors are listen-only — they can't swallow the
///     keystroke. That means the user's ⌥` would type a literal backtick
///     into whatever text field is focused every time they tap it, *and*
///     the synthesized ⌘V from `Paster` races with the still-processing
///     keystroke. Users saw both problems.
///   * `CGEventTap` lets us return `nil` from the callback to consume the
///     event. The keystroke never reaches the focused app. Matches
///     SuperWhisper / Raycast behavior.
///
/// Chord path (non-modifier key + modifiers): consumed.
/// Modifier-only path (bare ⌥ / ⌘ / ⌃ / ⇧): *not* consumed — modifiers
/// alone don't produce text and users often combine them with other
/// shortcuts, so swallowing them would break normal typing.
///
/// Accessibility permission is required for CGEventTap. We gate install
/// on the AX check and poll in the background until the user grants it —
/// no relaunch required.
@MainActor
final class HotkeyMonitor {
    /// Called when the user presses the configured hotkey. In tap-to-toggle
    /// UX this fires once per keystroke; the downstream state machine
    /// decides whether it means "start" or "stop".
    var onToggle: (() -> Void)?

    /// Fires on the main actor whenever `isInstalled` flips. Useful for
    /// surfacing a "Waiting for Accessibility permission" state in the UI.
    var onInstalledChange: ((Bool) -> Void)?

    /// True when the global event tap is live and we'll actually hear hotkey
    /// events. Observable via `onInstalledChange`.
    private(set) var isInstalled = false {
        didSet { if oldValue != isInstalled { onInstalledChange?(isInstalled) } }
    }

    private let config: AppConfig
    private let log = Logger(subsystem: "com.local.murmur", category: "hotkey")

    // CGEventTap plumbing. Tap lifetime is bounded by start()/stop().
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTask: Task<Void, Never>?

    // State (all touched only on main actor).
    private var modifierHeld = false            // for down-edge detection on modifier-only path
    private var lastToggleAt: CFAbsoluteTime = 0

    init(config: AppConfig) {
        self.config = config
    }

    /// Starts listening. Prompts for Accessibility permission if not yet
    /// granted. If denied, begins a background poll that installs the
    /// tap the moment the user grants access — no relaunch required.
    /// Returns whether the tap is currently live.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        _ = requestAccessibility(prompt: true)

        if installEventTap() {
            return true
        }

        log.warning("Hotkey tap not installed yet — polling for Accessibility grant.")
        startRetryLoop()
        return false
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        modifierHeld = false
        isInstalled = false
    }

    /// Tear the tap down and install it again against the current
    /// `config.hotkey`. Called when the user picks a new hotkey in Settings
    /// so the change takes effect without a relaunch.
    func restart() {
        log.info("Hotkey restart requested")
        stop()
        _ = start()
    }

    // MARK: - Tap install + retry loop

    @discardableResult
    private func installEventTap() -> Bool {
        guard isAccessibilityTrusted() else {
            log.warning("TCC gate not open — Accessibility=false")
            return false
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // .defaultTap = we can modify/consume
            eventsOfInterest: mask,
            callback: Self.tapCallback,
            userInfo: refcon
        ) else {
            log.error("CGEvent.tapCreate returned nil")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        let key = HotkeyKey.parse(config.hotkey)
        log.info("Hotkey tap installed: \(key.displayName, privacy: .public)")
        isInstalled = true
        return true
    }

    private func startRetryLoop() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                let installed = await MainActor.run { () -> Bool in
                    guard let self else { return true }
                    return self.installEventTap()
                }
                if installed { return }
            }
        }
    }

    // MARK: - CGEventTap callback

    /// C-compatible trampoline. Unpacks the `HotkeyMonitor` from the
    /// refcon pointer and dispatches to the instance handler.
    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        return monitor.handle(type: type, event: event)
    }

    /// Returns `nil` to consume the event, or an unmanaged reference to
    /// the (possibly modified) event to let it through. Called on the
    /// event tap's thread — must be fast and thread-safe. State reads use
    /// `MainActor.assumeIsolated` because the tap is scheduled on the
    /// main run loop.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // System disabled the tap — typically after heavy background work
        // causes a timeout. Re-enable so hotkeys don't silently stop working.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Tap is scheduled on the main run loop, so `self` is effectively
        // main-actor isolated at the point of this call.
        return MainActor.assumeIsolated {
            let configured = HotkeyKey.parse(config.hotkey)

            switch configured {
            case .chord(let targetKc, let targetMods, _):
                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }
                guard kc == targetKc else {
                    return Unmanaged.passUnretained(event)
                }
                // Exact modifier match so ⌥` doesn't also fire on ⌃⌥`.
                let have = deviceIndependent(from: flags)
                let need = targetMods.intersection(.deviceIndependentFlagsMask)
                guard have == need else {
                    return Unmanaged.passUnretained(event)
                }
                fireToggle()
                return nil                  // consume — the `  never reaches the focused app

            case .modifier(let targetKc, _):
                guard type == .flagsChanged else {
                    return Unmanaged.passUnretained(event)
                }
                guard kc == targetKc else {
                    return Unmanaged.passUnretained(event)
                }
                // Derive down-vs-up: `.flagsChanged` doesn't tell us
                // directly. Check whether the relevant modifier bit is
                // set in the event's flags.
                let bit = modifierBit(forKeycode: targetKc)
                let isDown = bit != nil && flags.contains(bit!)
                if isDown && !modifierHeld {
                    modifierHeld = true
                    fireToggle()
                } else if !isDown {
                    modifierHeld = false
                }
                // Never consume modifier-only events — users combine ⌥
                // etc. with other shortcuts for normal work.
                return Unmanaged.passUnretained(event)
            }
        }
    }

    /// Convert `CGEventFlags` to `NSEvent.ModifierFlags` restricted to
    /// device-independent bits (matches how `HotkeyKey.chord` stores its
    /// modifier requirement).
    private nonisolated func deviceIndependent(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var mods: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand)    { mods.insert(.command) }
        if flags.contains(.maskAlternate)  { mods.insert(.option) }
        if flags.contains(.maskControl)    { mods.insert(.control) }
        if flags.contains(.maskShift)      { mods.insert(.shift) }
        return mods
    }

    /// Which `CGEventFlags` bit toggles for a given modifier keycode.
    /// Used to distinguish the down vs up edge of a bare modifier tap.
    private nonisolated func modifierBit(forKeycode keycode: CGKeyCode) -> CGEventFlags? {
        switch keycode {
        case 54, 55:      return .maskCommand   // Right/Left Command
        case 58, 61:      return .maskAlternate // Left/Right Option
        case 59, 62:      return .maskControl   // Left/Right Control
        case 56, 60:      return .maskShift     // Left/Right Shift
        default:          return nil
        }
    }

    /// Fires `onToggle` unless a prior toggle fired too recently (bounce /
    /// auto-repeat debounce).
    private func fireToggle() {
        let now = CFAbsoluteTimeGetCurrent()
        let debounce = max(0.15, min(1.0, config.minPressDurationS))
        if now - lastToggleAt < debounce {
            log.debug("Hotkey toggle debounced (Δ=\(now - self.lastToggleAt, privacy: .public)s)")
            return
        }
        lastToggleAt = now
        log.info("Hotkey toggle")
        onToggle?()
    }

    // MARK: - Accessibility permission

    /// Returns true if granted. When `prompt` is true, the system dialog +
    /// System Settings entry are created the first time it's called
    /// without permission. Pass `prompt=false` for periodic polling so we
    /// don't re-trigger the dialog.
    @discardableResult
    private func requestAccessibility(prompt: Bool) -> Bool {
        let optKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [optKey: (prompt ? kCFBooleanTrue : kCFBooleanFalse) as Any] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Silent variant used by the retry loop; does not surface a prompt.
    private func isAccessibilityTrusted() -> Bool {
        requestAccessibility(prompt: false)
    }
}
