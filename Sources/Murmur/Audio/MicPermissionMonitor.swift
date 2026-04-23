import AVFoundation
import Foundation
import OSLog

/// Observes macOS microphone (`AVMediaType.audio`) TCC state.
///
/// Why this exists as a dedicated monitor (rather than living inside
/// `Recorder`):
///   * `Recorder` is hot-path audio-engine code (start/stop/encode).
///     Folding in a long-lived poll loop would muddle responsibilities.
///   * `AppDelegate` wants to know about mic status independent of a
///     recording session — to drive the menubar warning + sequence the
///     API-key prompt after mic has been requested.
///
/// The shape mirrors `HotkeyMonitor`: a `start()` that (a) triggers the
/// system TCC prompt the first time it's ever called via
/// `AVCaptureDevice.requestAccess`, and (b) begins a 2-second polling
/// task that notices when the user flips the switch later in
/// System Settings — macOS doesn't publish a notification for this.
@MainActor
final class MicPermissionMonitor {
    /// Fires on the main actor every time the status changes (including
    /// the first time `start()` resolves). Never fires twice in a row with
    /// the same value.
    var onStatusChange: ((AVAuthorizationStatus) -> Void)?

    private(set) var status: AVAuthorizationStatus = .notDetermined

    private let log = Logger(subsystem: "com.local.murmur", category: "mic")
    private var pollTask: Task<Void, Never>?

    /// Read the current TCC status. If `.notDetermined`, trigger the
    /// system prompt (so Murmur becomes visible in System Settings →
    /// Privacy → Microphone). Either way, begin polling for transitions
    /// so toggles in System Settings are picked up live.
    func start() {
        let current = AVCaptureDevice.authorizationStatus(for: .audio)
        log.info("start: initial=\(String(describing: current), privacy: .public)")

        if current == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                // Completion callback fires off an arbitrary queue.
                Task { @MainActor [weak self] in
                    self?.deliver(granted ? .authorized : .denied)
                }
            }
        } else {
            // Fire once synchronously (through the main actor) so the UI
            // reflects the stored grant without waiting for a poll tick.
            deliver(current)
        }

        startPollLoop()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Polling

    /// 2-second tick to pick up user-driven toggles in System Settings.
    /// Mirrors `HotkeyMonitor.startRetryLoop` — same tolerances, same
    /// cancellation behavior.
    private func startPollLoop() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self else { return }
                    let current = AVCaptureDevice.authorizationStatus(for: .audio)
                    if current != self.status {
                        self.deliver(current)
                    }
                }
            }
        }
    }

    /// Update cached status and fan out to `onStatusChange`. De-duped so
    /// repeated identical polls don't spam the callback.
    private func deliver(_ new: AVAuthorizationStatus) {
        guard new != status else { return }
        status = new
        log.info("status -> \(String(describing: new), privacy: .public)")
        onStatusChange?(new)
    }
}
