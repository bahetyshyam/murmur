import AppKit
import Foundation

/// Lightweight first-run flow: checks a UserDefaults flag and, on first
/// launch, pops an NSAlert with deep-links to each privacy pane the app
/// needs (Microphone / Accessibility / Input Monitoring).
///
/// Kept intentionally simple — a full SwiftUI onboarding wizard is overkill
/// for a personal tool. The alert + deep-link buttons cover the ground
/// the user actually needs to traverse.
@MainActor
enum Onboarding {
    private static let seenKey = "onboardingSeen.v1"

    static func runIfFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seenKey) else { return }
        show(firstRun: true)
        defaults.set(true, forKey: seenKey)
    }

    /// Re-runnable from the menubar "Permissions Help" item.
    static func showPermissionsHelp() {
        show(firstRun: false)
    }

    private static func show(firstRun: Bool) {
        let alert = NSAlert()
        alert.messageText = firstRun ? "Welcome to Murmur" : "Permissions"
        alert.informativeText = """
        Murmur needs two macOS permissions to work:

        • Microphone — to record audio while you hold the hotkey.
        • Accessibility — both to detect your push-to-talk key globally \
        and to synthesize a ⌘V keystroke for paste.

        You'll be prompted as features are used. You can also grant them \
        manually in System Settings → Privacy & Security. Use the buttons \
        below to jump directly to each pane.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Microphone")
        alert.addButton(withTitle: "Open Accessibility")
        alert.addButton(withTitle: "Done")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            openPane("Privacy_Microphone")
            show(firstRun: false) // re-show so user can visit both panes
        case .alertSecondButtonReturn:
            openPane("Privacy_Accessibility")
            show(firstRun: false)
        default:
            break
        }
    }

    private static func openPane(_ name: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(name)")!
        NSWorkspace.shared.open(url)
    }
}
