import AppKit

/// Owns the NSStatusItem and its menu. Icon glyph is driven by
/// `AppModel.state` via `apply(state:)`.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    weak var appModel: AppModel?

    private var stateItem: NSMenuItem?  // the "Idle / Recording…" row
    private var permissionItem: NSMenuItem?        // status row (hidden when OK)
    private var grantItem: NSMenuItem?             // "Grant Accessibility Access…" deep-link
    private var micPermissionItem: NSMenuItem?     // "Microphone access required" status row
    private var micGrantItem: NSMenuItem?          // "Grant Microphone Access…" deep-link
    private var lastState: AppModel.State = .idle
    private var hotkeyInstalled = true
    // Default to true so the menubar doesn't flash a false "mic missing"
    // warning during the brief window between launch and the first
    // MicPermissionMonitor.start() callback.
    private var micGranted = true

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton(glyph: .idle)
        statusItem.menu = buildMenu()
    }

    /// Called from AppModel.applyStateChange.
    func apply(state: AppModel.State) {
        lastState = state
        refreshIconAndLabel()
    }

    /// Called by AppDelegate when the hotkey tap install state changes
    /// (e.g. user grants Accessibility — polling picks it up live).
    func apply(hotkeyInstalled installed: Bool) {
        hotkeyInstalled = installed
        permissionItem?.isHidden = installed
        grantItem?.isHidden = installed
        refreshIconAndLabel()
    }

    /// Called by AppDelegate when MicPermissionMonitor reports a status
    /// change. `granted` is true only for `.authorized` — `.denied` and
    /// `.restricted` both surface the warning row.
    func apply(micGranted granted: Bool) {
        micGranted = granted
        micPermissionItem?.isHidden = granted
        micGrantItem?.isHidden = granted
        refreshIconAndLabel()
    }

    /// Precedence: Accessibility wins, because without it the hotkey tap
    /// isn't installed at all (and fixing mic first wouldn't help the user
    /// do anything). Only show the mic warning when AX is already fine.
    private func refreshIconAndLabel() {
        if !hotkeyInstalled {
            configureButton(glyph: .error)
            stateItem?.title = "Hotkey disabled — grant Accessibility"
        } else if !micGranted {
            configureButton(glyph: .error)
            stateItem?.title = "Microphone access needed"
        } else {
            configureButton(glyph: MurmurIcon.glyphState(for: lastState))
            stateItem?.title = Self.stateLabel(for: lastState)
        }
    }

    // MARK: - Building

    private func configureButton(glyph state: MurmurIcon.GlyphState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .error:
            // Yellow multi-color warning triangle — matches the familiar
            // macOS "attention" affordance. Non-template so the fill stays.
            let image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "Murmur — attention needed"
            )
            image?.isTemplate = false
            button.image = image
        default:
            // 18pt matches native SF Symbol menubar height; template image
            // lets macOS tint for light/dark/accented menubars.
            button.image = MurmurIcon.menubarGlyph(state, size: 18)
        }
        button.toolTip = "Murmur"
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Murmur", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let state = NSMenuItem(title: Self.stateLabel(for: .idle), action: nil, keyEquivalent: "")
        state.isEnabled = false
        stateItem = state
        menu.addItem(state)

        // Permission-state row + direct deep-link action. Both are hidden
        // while the tap is live; shown the moment install fails. The
        // session-level CGEventTap only needs Accessibility — no Input
        // Monitoring grant required (we restrict hotkeys to modifier-only
        // so `.flagsChanged` is all we consume).
        let perm = NSMenuItem(title: "Hotkey disabled — grant Accessibility", action: nil, keyEquivalent: "")
        perm.isEnabled = false
        perm.isHidden = true
        permissionItem = perm
        menu.addItem(perm)

        let grant = actionItem("Grant Accessibility Access…", #selector(openAccessibilityPane(_:)))
        grant.isHidden = true
        grantItem = grant
        menu.addItem(grant)

        // Parallel mic rows — only surface after AX is granted (see the
        // precedence rule in refreshIconAndLabel). By the time the user
        // reaches this row, MicPermissionMonitor.start() has already
        // called AVCaptureDevice.requestAccess, so Murmur is registered
        // with TCC and the deep-linked Privacy → Microphone pane will
        // actually list it.
        let micPerm = NSMenuItem(title: "Microphone access required", action: nil, keyEquivalent: "")
        micPerm.isEnabled = false
        micPerm.isHidden = true
        micPermissionItem = micPerm
        menu.addItem(micPerm)

        let micGrant = actionItem("Grant Microphone Access…", #selector(openMicrophonePane(_:)))
        micGrant.isHidden = true
        micGrantItem = micGrant
        menu.addItem(micGrant)

        menu.addItem(.separator())

        menu.addItem(actionItem("History…", #selector(openHistory(_:))))
        menu.addItem(actionItem("Settings…", #selector(openSettings(_:)), keyEquivalent: ","))
        menu.addItem(actionItem("Permissions Help…", #selector(openPermissions(_:))))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Murmur",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        return menu
    }

    private func actionItem(_ title: String, _ action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    // MARK: - Menu targets

    @objc private func openHistory(_ sender: Any?)     { appModel?.showHistoryWindow() }
    @objc private func openSettings(_ sender: Any?)    { appModel?.showSettingsWindow() }
    @objc private func openPermissions(_ sender: Any?) { appModel?.showPermissionsHelp() }

    @objc private func openAccessibilityPane(_ sender: Any?) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openMicrophonePane(_ sender: Any?) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Label mapping

    private static func stateLabel(for state: AppModel.State) -> String {
        switch state {
        case .idle:              return "Idle"
        case .recording:         return "Recording…"
        case .transcribing:      return "Transcribing…"
        case .error(let message): return "Error: \(message)"
        }
    }
}
