import AppKit
import OSLog

/// Top-level app lifecycle. Holds strong references to the object graph
/// so nothing gets deallocated after `applicationDidFinishLaunching`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.local.murmur", category: "app")

    // Strong references — lose any of these and bits of the app go dark.
    private var config: AppConfig?
    private var history: HistoryStore?
    private var model: AppModel?
    private var menuBar: MenuBarController?
    private var hotkey: HotkeyMonitor?
    private var windows: WindowManager?

    /// Guards the "no API key → prompt" flow so we don't badger the user
    /// every time accessibility re-negotiates during a session.
    private var hasCheckedForApiKey = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { bootstrap() }
    }

    @MainActor
    private func bootstrap() {
        // App icon (Ink-palette Dot). LSUIElement=YES hides the dock tile,
        // but the same image flows into notifications, About dialog, and
        // Finder's "Get Info" — so setting it here matters even for a
        // menubar-only app.
        NSApp.applicationIconImage = MurmurIcon.appIcon(size: 512)

        // Install standard Edit/Quit/Minimize/Close shortcuts. Required for
        // LSUIElement apps — without this, ⌘V (paste) silently fails in
        // the Settings window's API Key field and macOS plays the error
        // beep.
        AppMenu.install()

        let config = AppConfig()
        let history: HistoryStore
        do {
            history = try HistoryStore()
        } catch {
            log.fault("HistoryStore init failed: \(String(describing: error), privacy: .public) — falling back to in-memory")
            // Fallback so the app still runs; the user won't get history
            // persistence this session, but the core pipeline works.
            history = try! HistoryStore.inMemory()
        }

        let menuBar = MenuBarController()
        let windows = WindowManager(config: config, history: history)
        let model = AppModel(config: config, history: history)

        menuBar.appModel = model
        model.menuBar = menuBar
        model.windows = windows
        menuBar.apply(state: model.state)

        // Hotkey install. If Accessibility isn't yet granted, the user
        // gets a TCC prompt AND the monitor keeps polling in the
        // background — the moment the user grants access, the tap goes
        // live with no relaunch.
        let hotkey = HotkeyMonitor(config: config)
        hotkey.onToggle = { [weak model] in model?.hotkeyToggled() }
        hotkey.onInstalledChange = { [weak self, weak menuBar] installed in
            menuBar?.apply(hotkeyInstalled: installed)
            if installed {
                self?.promptForApiKeyIfMissing()
            }
        }
        let installed = hotkey.start()
        menuBar.apply(hotkeyInstalled: installed)

        // Settings posts `.murmurHotkeyChanged` after writing the new chord
        // to `config.hotkey`; we rebuild the monitor so the change takes
        // effect without a relaunch.
        NotificationCenter.default.addObserver(
            forName: .murmurHotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak hotkey] _ in
            MainActor.assumeIsolated { hotkey?.restart() }
        }

        self.config = config
        self.history = history
        self.menuBar = menuBar
        self.model = model
        self.hotkey = hotkey
        self.windows = windows

        logKeychainStatus()

        // First-run onboarding (NSAlert with deep-links to Privacy panes).
        // Fires once; after that the "Permissions Help" menu item re-opens
        // the same alert.
        Onboarding.runIfFirstLaunch()

        // If Accessibility is already granted at launch (returning user),
        // the hotkey monitor installs synchronously and `onInstalledChange`
        // never fires. Check now so the API-key prompt still shows.
        if installed {
            promptForApiKeyIfMissing()
        }
    }

    /// Shows an NSAlert pointing the user at the Settings → API Key tab
    /// if the Keychain slot is empty. Idempotent within a launch:
    /// subsequent Accessibility toggles don't re-prompt.
    @MainActor
    private func promptForApiKeyIfMissing() {
        guard !hasCheckedForApiKey else { return }
        hasCheckedForApiKey = true

        let keyPresent: Bool
        do {
            keyPresent = try (Keychain.read(Keychain.openAIKey)?.isEmpty == false)
        } catch {
            log.error("Keychain read during startup prompt failed: \(String(describing: error), privacy: .public)")
            return                              // don't pester on keychain errors
        }
        guard !keyPresent else { return }

        // Run off the tail of this callback so we don't present an NSAlert
        // from inside a hotkey-monitor callback (which can race with the
        // CGEventTap thread).
        DispatchQueue.main.async { [weak self] in
            self?.showApiKeyPrompt()
        }
    }

    @MainActor
    private func showApiKeyPrompt() {
        let alert = NSAlert()
        alert.messageText = "Add your OpenAI API key"
        alert.informativeText =
            "Murmur needs an OpenAI API key to transcribe what you say. " +
            "You can paste one into Settings now, or add it later from the menubar."
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Open Settings…")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            windows?.showSettings(preferredTab: .apiKey)
        }
    }

    @MainActor
    private func logKeychainStatus() {
        do {
            if let key = try Keychain.read(Keychain.openAIKey) {
                log.info("Keychain: found OpenAI key (length=\(key.count, privacy: .public))")
            } else {
                log.info("Keychain: no OpenAI key stored (first run or cleared)")
            }
        } catch {
            log.error("Keychain read failed: \(String(describing: error), privacy: .public)")
        }
    }
}
