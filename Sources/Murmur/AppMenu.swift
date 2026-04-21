import AppKit

/// Builds and installs the standard macOS main menu.
///
/// Why an accessory app (`LSUIElement=YES`) still needs a main menu:
/// the menu bar is hidden, but Cocoa routes text-editing keyboard
/// shortcuts (⌘C/⌘V/⌘X/⌘A/⌘Z) through the Edit menu's key equivalents.
/// Without an Edit menu, `SecureField` / `TextField` silently ignore
/// paste and macOS plays the beep. Installing the menu with standard
/// selectors fixes it without adding any visible chrome.
enum AppMenu {
    static func install() {
        let main = NSMenu()

        // App menu — hidden for LSUIElement apps, but the Quit shortcut
        // still needs to live somewhere so `⌘Q` terminates cleanly.
        let appItem = NSMenuItem()
        let appSubmenu = NSMenu()
        appSubmenu.addItem(withTitle: "About Murmur",
                           action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                           keyEquivalent: "")
        appSubmenu.addItem(.separator())
        appSubmenu.addItem(withTitle: "Hide Murmur",
                           action: #selector(NSApplication.hide(_:)),
                           keyEquivalent: "h")
        appSubmenu.addItem(.separator())
        appSubmenu.addItem(withTitle: "Quit Murmur",
                           action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q")
        appItem.submenu = appSubmenu
        main.addItem(appItem)

        // Edit menu — this is the load-bearing one. Uses `Selector(("…:"))`
        // style for undo/redo because those aren't on NSResponder directly;
        // Cocoa walks the responder chain and AppKit's NSTextView handles
        // them.
        let editItem = NSMenuItem()
        let editSubmenu = NSMenu(title: "Edit")
        editSubmenu.addItem(withTitle: "Undo",
                            action: Selector(("undo:")),
                            keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo",
                              action: Selector(("redo:")),
                              keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editSubmenu.addItem(redo)
        editSubmenu.addItem(.separator())
        editSubmenu.addItem(withTitle: "Cut",
                            action: #selector(NSText.cut(_:)),
                            keyEquivalent: "x")
        editSubmenu.addItem(withTitle: "Copy",
                            action: #selector(NSText.copy(_:)),
                            keyEquivalent: "c")
        editSubmenu.addItem(withTitle: "Paste",
                            action: #selector(NSText.paste(_:)),
                            keyEquivalent: "v")
        editSubmenu.addItem(withTitle: "Select All",
                            action: #selector(NSText.selectAll(_:)),
                            keyEquivalent: "a")
        editItem.submenu = editSubmenu
        main.addItem(editItem)

        // Window menu — same story: `⌘W` / `⌘M` key equivalents need to
        // live somewhere on the main menu to work on NSWindows opened by
        // the app (Settings, History).
        let windowItem = NSMenuItem()
        let windowSubmenu = NSMenu(title: "Window")
        windowSubmenu.addItem(withTitle: "Minimize",
                              action: #selector(NSWindow.performMiniaturize(_:)),
                              keyEquivalent: "m")
        windowSubmenu.addItem(withTitle: "Close",
                              action: #selector(NSWindow.performClose(_:)),
                              keyEquivalent: "w")
        windowItem.submenu = windowSubmenu
        NSApp.windowsMenu = windowSubmenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
