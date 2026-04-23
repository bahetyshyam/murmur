import AppKit
import Foundation

/// Entry points for first-run onboarding + the menubar "Permissions Help"
/// action. Both present the same SwiftUI wizard (`OnboardingWizardView`).
///
/// Keeps a single persistent NSWindow reference so repeat invocations
/// don't stack windows, and so closing the wizard during active use
/// (e.g. user hits ⌘W) doesn't dealloc model state mid-flight.
@MainActor
enum Onboarding {
    private static let seenKey = "onboardingSeen.v1"
    private static var hostedWindow: NSWindow?

    /// Called once during bootstrap. Opens the wizard on true first launch
    /// only; subsequent launches no-op. Non-blocking — the rest of app
    /// bootstrap continues while the wizard is on screen so permissions
    /// granted through the wizard flow straight into the already-running
    /// HotkeyMonitor / MicPermissionMonitor.
    static func runIfFirstLaunch(config: AppConfig, windows: WindowManager?) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seenKey) else { return }
        present(config: config, windows: windows, markSeenOnFinish: true)
    }

    /// Re-runnable from the menubar "Permissions Help" item.
    static func showPermissionsHelp(config: AppConfig, windows: WindowManager?) {
        present(config: config, windows: windows, markSeenOnFinish: false)
    }

    // MARK: -

    private static func present(
        config: AppConfig,
        windows: WindowManager?,
        markSeenOnFinish: Bool
    ) {
        if let window = hostedWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let model = OnboardingModel(config: config)
        let window = OnboardingWindow.make(model: model) {
            if markSeenOnFinish {
                UserDefaults.standard.set(true, forKey: Self.seenKey)
            }
            hostedWindow?.close()
            // willClose observer handles the rest (activation policy +
            // nil'ing hostedWindow), so both the Finish path and red-X
            // path converge on the same teardown.
        }
        hostedWindow = window

        // Switch to a regular app while the wizard is up so macOS treats
        // Murmur as a focus-eligible app after TCC / System Settings
        // round-trips. Without this, a menubar-only (.accessory) app
        // vanishes from ⌘Tab + the dock the moment the system dialog
        // dismisses — and the wizard becomes impossible to refocus
        // without Mission Control. Mirrors freeflow's approach.
        NSApp.setActivationPolicy(.regular)

        // Observe willClose so the red-X and ⌘W paths restore .accessory
        // identically to the Finish path. Captured `token` lets the
        // observer remove itself — important because
        // isReleasedWhenClosed=false means the NSWindow sticks around
        // (hidden) and we don't want a dangling observer firing again on
        // a re-opened window later.
        // Box the observer token so the closure can read it after it's
        // assigned below, without capturing a mutable `var` (which Swift
        // 5.10 strict concurrency rejects from a Sendable closure).
        final class TokenBox: @unchecked Sendable { var token: NSObjectProtocol? }
        let box = TokenBox()
        box.token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            // Queue is .main, so we're on the main thread — safe to
            // assume main-actor isolation and touch NSApp + the
            // static `hostedWindow` ref.
            MainActor.assumeIsolated {
                if let token = box.token {
                    NotificationCenter.default.removeObserver(token)
                }
                NSApp.setActivationPolicy(.accessory)
                hostedWindow = nil
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
