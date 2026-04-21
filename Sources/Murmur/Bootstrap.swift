import AppKit

/// Public entry point so the thin `MurmurApp` executable target can
/// launch the app without needing visibility into `AppDelegate` itself.
/// Kept tiny and AppKit-native so the app works when launched from inside
/// a .app bundle (the bundle identity is what makes NSStatusItem actually
/// render on screen on macOS 14+ — the whole reason we rewrote out of Python).
public enum MurmurLauncher {
    /// Strong-reference the delegate so `NSApp` (which holds it weakly)
    /// doesn't lose it.
    nonisolated(unsafe) private static var retainedDelegate: AppDelegate?

    public static func run() -> Never {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        // Accessory = menubar-only app, no Dock icon, no main menu focus-steal.
        app.setActivationPolicy(.accessory)
        app.run()
        // NSApplication.run() actually returns on terminate, so:
        exit(0)
    }
}
