import AppKit
import OSLog
import Sparkle

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController`.
///
/// Owns the updater for the app's lifetime (held strongly by `AppDelegate`,
/// the same way `HotkeyMonitor` / `MicPermissionMonitor` are). Sparkle runs
/// its own background scheduler, so once started it checks on its own
/// `SUScheduledCheckInterval` cadence — no manual timer here.
///
/// Update settings come from two places that we keep in sync:
///   * `Info.plist` (`SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`,
///     `SUAutomaticallyUpdate`, `SUScheduledCheckInterval`) — the values
///     Sparkle reads at startup.
///   * `AppConfig.autoCheckUpdates` — the user-facing toggle, applied live
///     to the running updater via `applyAutoCheckPreference()` so flipping it
///     in Settings takes effect without a relaunch.
///
/// We ship self-signed (not notarized): Sparkle's security rests on the
/// EdDSA signature over each update archive (verified against `SUPublicEDKey`)
/// plus a code-signature *consistency* check against the running app. Every
/// build is signed with the same `Murmur Dev` identity, so that check passes.
@MainActor
final class Updater {
    private let log = Logger(subsystem: "com.local.murmur", category: "updater")
    private let config: AppConfig
    private let controller: SPUStandardUpdaterController
    private let delegate = UpdaterLoggingDelegate()

    init(config: AppConfig) {
        self.config = config
        // `startingUpdater: true` boots the updater immediately, which reads
        // the feed URL + public key from Info.plist and arms the background
        // scheduler.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        applyAutoCheckPreference()
        log.info("Updater started — feed=\(self.controller.updater.feedURL?.absoluteString ?? "<none>", privacy: .public)")
    }

    /// Manual "Check for Updates…" from the menubar. Always shows UI — even
    /// when the app is already up to date — because the user explicitly asked.
    func checkForUpdates() {
        log.info("Manual update check requested")
        controller.checkForUpdates(nil)
    }

    /// Push `config.autoCheckUpdates` into the live updater. With the toggle
    /// on we both auto-check *and* auto-download/install in the background
    /// (silent updates, applied on next relaunch); off disables scheduled
    /// checks entirely. The manual menu item works regardless.
    func applyAutoCheckPreference() {
        let enabled = config.autoCheckUpdates
        controller.updater.automaticallyChecksForUpdates = enabled
        controller.updater.automaticallyDownloadsUpdates = enabled
        log.info("Automatic update checks \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
}

/// Minimal `SPUUpdaterDelegate` that funnels Sparkle's lifecycle into our
/// unified `OSLog` subsystem. `nonisolated` because Sparkle invokes delegate
/// callbacks without an actor context; the logger is `Sendable`.
private final class UpdaterLoggingDelegate: NSObject, SPUUpdaterDelegate {
    private let log = Logger(subsystem: "com.local.murmur", category: "updater")

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        log.info("Appcast loaded — \(appcast.items.count, privacy: .public) item(s)")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        log.info("Update available: \(item.displayVersionString, privacy: .public)")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        log.info("No update found: \(error.localizedDescription, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        log.error("Updater aborted: \(error.localizedDescription, privacy: .public)")
    }
}
