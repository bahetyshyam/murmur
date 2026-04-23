import AppKit
import Foundation
import Observation
import OSLog

/// Central @Observable state machine for the app. Orchestrates
/// recorder → transcriber → paster → history, and drives menubar icon,
/// HUD, and chime playback through `applyStateChange`.
///
///   IDLE → RECORDING → TRANSCRIBING → IDLE
///                   ↘                ↗
///                     ERROR (3 s auto-clear) →
@Observable
@MainActor
final class AppModel {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)
    }

    var state: State = .idle {
        didSet { applyStateChange(from: oldValue, to: state) }
    }

    let config: AppConfig
    let history: HistoryStore
    let recorder = Recorder()
    let paster = Paster()
    let chimes = Chimes()
    let hud: HUDController

    /// UI references — set post-init by AppDelegate; weak to avoid cycles.
    weak var menuBar: MenuBarController?
    weak var windows: WindowManager?

    private let log = Logger(subsystem: "com.local.murmur", category: "state")
    private var errorClearTask: Task<Void, Never>?
    private var recordStartedAt: CFAbsoluteTime = 0

    init(config: AppConfig, history: HistoryStore) {
        self.config = config
        self.history = history
        self.hud = HUDController(recorder: recorder)
        chimes.preload()
        // Prune old history on launch (parity with Python prototype).
        let deleted = history.prune(retentionDays: config.historyRetentionDays)
        if deleted > 0 {
            log.info("Pruned \(deleted, privacy: .public) transcripts older than \(config.historyRetentionDays, privacy: .public) days")
        }
    }

    // MARK: - Hotkey-driven transitions

    /// Single entry point for the tap-to-toggle hotkey. Flips idle ↔
    /// recording; ignored while already transcribing or sitting in an
    /// error state (auto-clears after 3s, same as before).
    func hotkeyToggled() {
        switch state {
        case .idle:
            do {
                try recorder.start()
                recordStartedAt = CFAbsoluteTimeGetCurrent()
                state = .recording
                if config.chimesEnabled { chimes.playStart() }
            } catch RecorderError.microphoneDenied {
                log.error("recorder.start failed: microphone denied")
                enterError("Microphone access denied — see menu")
            } catch {
                log.error("recorder.start failed: \(String(describing: error), privacy: .public)")
                enterError("Recording failed to start")
            }
        case .recording:
            state = .transcribing
            let duration = CFAbsoluteTimeGetCurrent() - recordStartedAt
            let tailMs = config.releaseTailMs
            Task { [weak self] in
                await self?.transcribeAndPaste(durationS: duration, tailMs: tailMs)
            }
        case .transcribing, .error:
            log.debug("hotkeyToggled ignored — state=\(String(describing: self.state), privacy: .public)")
        }
    }

    // MARK: - Pipeline

    private func transcribeAndPaste(durationS: Double, tailMs: Int) async {
        // 1. Stop mic + drain tail.
        let wav: Data
        do {
            wav = try await recorder.stop(tailMs: tailMs)
        } catch {
            log.error("recorder.stop failed: \(String(describing: error), privacy: .public)")
            enterError("Recording failed")
            return
        }

        // 2. Load API key at call time so Settings edits take effect
        //    without a relaunch.
        let apiKey: String
        do {
            guard let k = try Keychain.read(Keychain.openAIKey), !k.isEmpty else {
                enterError("No API key — open Settings")
                return
            }
            apiKey = k
        } catch {
            enterError("Keychain unavailable")
            return
        }

        // 3. Upload.
        let transcriber = Transcriber(
            apiKey: apiKey,
            model: config.model,
            biasingPrompt: config.biasingPrompt,
            language: config.language
        )

        let text: String
        do {
            text = try await transcriber.transcribe(wav: wav)
        } catch let e as TranscriberError {
            history.append(
                text: "", model: config.model, durationS: durationS,
                error: e.description
            )
            enterError(e.userMessage)
            return
        } catch {
            history.append(
                text: "", model: config.model, durationS: durationS,
                error: String(describing: error)
            )
            enterError("Transcription failed")
            return
        }

        // 4. Persist before paste — so if paste fails the text is still
        //    recoverable from the History window. The Usage tab derives
        //    its numbers from this table, so the row doubles as the
        //    spend record.
        let rowId = history.append(
            text: text, model: config.model, durationS: durationS
        )

        // 5. Paste.
        if config.pasteAtCursor {
            do {
                try paster.paste(text: text, restoreClipboard: config.restoreClipboard)
                history.markPasted(rowId)
                if config.chimesEnabled { chimes.playEnd() }
                state = .idle
            } catch {
                log.error("paste failed: \(String(describing: error), privacy: .public)")
                // Still mark end chime + leave text on clipboard; the
                // user can paste manually. History row is already saved.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                if config.chimesEnabled { chimes.playEnd() }
                enterError("Paste failed — saved to History")
            }
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            history.markPasted(rowId)
            if config.chimesEnabled { chimes.playEnd() }
            state = .idle
        }
    }

    // MARK: - Error helper

    private func enterError(_ message: String) {
        if config.chimesEnabled { chimes.playError() }
        state = .error(message)
    }

    // MARK: - State dispatch

    private func applyStateChange(from old: State, to new: State) {
        log.info("state: \(String(describing: old), privacy: .public) → \(String(describing: new), privacy: .public)")

        menuBar?.apply(state: new)

        if config.hudEnabled {
            switch new {
            case .recording:    hud.show(.recording)
            case .transcribing: hud.show(.transcribing)
            case .idle, .error: hud.hide()
            }
        } else {
            hud.hide()
        }

        errorClearTask?.cancel()
        if case .error = new {
            errorClearTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    if case .error = self.state { self.state = .idle }
                }
            }
        }
    }

    // MARK: - Menu actions (invoked from MenuBarController)

    func showHistoryWindow() { windows?.showHistory() }
    func showSettingsWindow() { windows?.showSettings() }
    func showPermissionsHelp() {
        Onboarding.showPermissionsHelp(config: config, windows: windows)
    }
}
