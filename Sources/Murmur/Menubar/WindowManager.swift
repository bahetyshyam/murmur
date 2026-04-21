import AppKit
import SwiftUI

/// Owns the (at most one) Settings window and History window. Re-uses the
/// same NSWindow across menu clicks so the user's position / size is
/// preserved between opens.
@MainActor
final class WindowManager {
    private weak var config: AppConfig?
    private weak var history: HistoryStore?

    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?

    init(config: AppConfig, history: HistoryStore) {
        self.config = config
        self.history = history
    }

    // MARK: - Settings

    func showSettings(preferredTab: SettingsView.Tab? = nil) {
        if settingsWindow == nil {
            guard let config, let history else { return }
            let host = NSHostingController(rootView: SettingsView(
                config: config,
                history: history,
                initialTab: preferredTab ?? .general
            ))
            let w = NSWindow(contentViewController: host)
            w.title = "Murmur Settings"
            // Resizable so the Settings tabs can grow when content
            // doesn't fit — paired with ScrollView inside each tab so
            // the TabView segmented control stays pinned at the top.
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // If the window already exists, switch tabs by notification —
        // replacing `rootView` would reset field state (partially-typed
        // API key, etc.) and feels glitchy.
        if let preferredTab {
            NotificationCenter.default.post(
                name: .murmurSelectSettingsTab,
                object: preferredTab
            )
        }
    }

    // MARK: - History

    func showHistory() {
        if historyWindow == nil {
            guard let history else { return }
            let host = NSHostingController(rootView: HistoryView(store: history))
            let w = NSWindow(contentViewController: host)
            w.title = "Murmur History"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 560, height: 420))
            w.isReleasedWhenClosed = false
            w.center()
            historyWindow = w
        }
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
