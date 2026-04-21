import AppKit
import OSLog

/// Plays short system sounds on state transitions.
/// Parity with the Python prototype's `sounds.py`:
///   * `playStart`  → "Pop"    (push-to-talk begins)
///   * `playEnd`    → "Tink"   (transcription finished + pasted OK)
///   * `playError`  → "Basso"  (transcription or paste failed)
///
/// Sounds are preloaded at launch; if macOS ever fails to locate one
/// (broken install, stripped system), we warn loudly so it surfaces in
/// the log stream instead of failing silently.
@MainActor
final class Chimes {
    private let log = Logger(subsystem: "com.local.murmur", category: "chimes")

    private var pop: NSSound?
    private var tink: NSSound?
    private var basso: NSSound?

    /// Called once at launch so first playback doesn't incur disk I/O.
    func preload() {
        pop = load("Pop")
        tink = load("Tink")
        basso = load("Basso")
    }

    func playStart() { restart(pop, label: "Pop") }
    func playEnd()   { restart(tink, label: "Tink") }
    func playError() { restart(basso, label: "Basso") }

    private func load(_ name: String) -> NSSound? {
        if let s = NSSound(named: NSSound.Name(name)) {
            return s
        }
        log.warning("System sound not found: \(name, privacy: .public)")
        return nil
    }

    private func restart(_ sound: NSSound?, label: String) {
        guard let sound else {
            log.warning("play(\(label, privacy: .public)) skipped — not preloaded")
            return
        }
        // `stop()+play()` resets an in-flight play so rapid re-triggers
        // still produce audible feedback (e.g. error → retry → error).
        sound.stop()
        sound.play()
    }
}
