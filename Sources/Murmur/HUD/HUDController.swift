import AppKit
import Observation
import SwiftUI

/// Manages a floating status panel that shows "Listening…" or
/// "Transcribing…" while a dictation session is in progress.
///
/// Implementation notes:
/// * `NSPanel` (not a window) with `nonactivatingPanel | borderless` so
///   focus doesn't steal from the user's app.
/// * `.statusBar` level so it floats above normal windows.
/// * `.canJoinAllSpaces + .fullScreenAuxiliary` so it appears on the
///   user's current Space (including full-screen apps).
/// * `ignoresMouseEvents = true` so clicks fall through to whatever's
///   underneath.
/// * Centered horizontally, positioned ~12 % from the top of the main
///   screen — far enough down to not overlap the menubar.
///
/// While `.recording`, a small observable `LevelHolder` mirrors the mic
/// RMS so the SwiftUI waveform inside `HUDView` can re-render without a
/// `@State` timer. The Recorder pushes levels; we pull them out on hide.
@MainActor
final class HUDController {
    /// Observable level mirror. Mutated on the main queue by Recorder's
    /// throttled callback; SwiftUI re-renders the waveform each time.
    @Observable
    final class LevelHolder {
        var level: Float = 0
    }

    private let recorder: Recorder
    let levelHolder = LevelHolder()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<HUDView>?
    private var currentMode: HUDView.Mode?

    init(recorder: Recorder) {
        self.recorder = recorder
    }

    /// Show (or update) the HUD.
    func show(_ mode: HUDView.Mode) {
        if panel == nil {
            build()
        }
        hostingView?.rootView = HUDView(mode: mode, levelHolder: levelHolder)
        currentMode = mode
        reposition()
        panel?.orderFrontRegardless()

        // Wire / un-wire the level callback based on mode. Only the
        // recording state needs the live meter.
        if mode == .recording {
            levelHolder.level = 0
            recorder.onLevel = { [weak self] level in
                // Recorder already dispatches to main; still assume on
                // main actor for the property touch.
                MainActor.assumeIsolated {
                    self?.levelHolder.level = level
                }
            }
        } else {
            recorder.onLevel = nil
        }
    }

    /// Hide the panel. Safe to call when already hidden.
    func hide() {
        recorder.onLevel = nil
        panel?.orderOut(nil)
        currentMode = nil
        levelHolder.level = 0
    }

    // MARK: - Panel construction

    private func build() {
        let initialRect = NSRect(x: 0, y: 0, width: 200, height: 42)
        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: HUDView(mode: .recording, levelHolder: levelHolder))
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host
        self.hostingView = host
        self.panel = panel
    }

    private func reposition() {
        guard let panel, let content = panel.contentView else { return }
        // Let SwiftUI decide the intrinsic size first.
        let fitting = content.fittingSize
        let width = max(fitting.width, 160)
        let height = max(fitting.height, 36)
        guard let screenFrame = NSScreen.main?.frame else { return }
        let x = screenFrame.midX - width / 2
        // ~12% from the top. Below the menubar, clearly visible.
        let y = screenFrame.maxY - height - screenFrame.height * 0.12
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
