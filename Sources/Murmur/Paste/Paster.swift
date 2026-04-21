import AppKit
import CoreGraphics
import OSLog

enum PasterError: Error, CustomStringConvertible {
    case cgEventCreateFailed
    case accessibilityDenied

    var description: String {
        switch self {
        case .cgEventCreateFailed: return "Paster.cgEventCreateFailed"
        case .accessibilityDenied: return "Paster.accessibilityDenied (grant Accessibility to Murmur)"
        }
    }
}

/// Pastes text at the cursor by writing to `NSPasteboard.general` and
/// then synthesizing a ⌘V keystroke. Optionally restores the previous
/// clipboard snapshot after a brief delay so the user's clipboard
/// history isn't clobbered.
@MainActor
final class Paster {
    private let log = Logger(subsystem: "com.local.murmur", category: "paster")
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Paste `text` into the currently focused app.
    ///
    /// - Parameters:
    ///   - text: the string to paste.
    ///   - restoreClipboard: if true, snapshots the existing pasteboard
    ///     contents first and restores them 250 ms after we post ⌘V so
    ///     the paste target has time to read them.
    ///
    /// Throws `PasterError.cgEventCreateFailed` if CGEvent construction
    /// fails (shouldn't happen in practice).
    func paste(text: String, restoreClipboard: Bool = true) throws {
        let snapshot = restoreClipboard ? Snapshot(pasteboard: pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try sendCommandV()

        if let snapshot {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                await MainActor.run {
                    snapshot.restore(to: self?.pasteboard)
                }
            }
        }
    }

    // MARK: - Private

    private func sendCommandV() throws {
        // Virtual keycode for V on US layouts. Yes, this is layout-specific,
        // but ⌘V is almost universally keycode 9 because macOS translates
        // by physical position, not character.
        let vKeyCode: CGKeyCode = 9

        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasterError.cgEventCreateFailed
        }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            throw PasterError.cgEventCreateFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand

        // .cgAnnotatedSessionEventTap ensures the event flows to the
        // focused app, not swallowed at a tap we installed.
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Snapshot

    private struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        init(pasteboard: NSPasteboard) {
            var captured: [[NSPasteboard.PasteboardType: Data]] = []
            for item in pasteboard.pasteboardItems ?? [] {
                var typeMap: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        typeMap[type] = data
                    }
                }
                if !typeMap.isEmpty { captured.append(typeMap) }
            }
            self.items = captured
        }

        func restore(to pasteboard: NSPasteboard?) {
            guard let pasteboard else { return }
            pasteboard.clearContents()
            let pbItems: [NSPasteboardItem] = items.map { typeMap in
                let item = NSPasteboardItem()
                for (type, data) in typeMap {
                    item.setData(data, forType: type)
                }
                return item
            }
            pasteboard.writeObjects(pbItems)
        }
    }
}
