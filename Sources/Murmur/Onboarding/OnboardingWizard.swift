import AppKit
import AVFoundation
import ApplicationServices
import Observation
import OSLog
import SwiftUI

// MARK: - Model

/// State + side-effects for the first-run wizard. The view binds directly
/// to these observables and nudges the model through `next()` / `back()`
/// and the per-step action methods.
///
/// Why `@Observable` on a class here: SwiftUI needs to re-render the
/// header dots, the canAdvance-driven Next button, and the per-step
/// permission status as values flip. `@Bindable` in the view handles the
/// two-way bindings (apiKey field, hotkey picker) for free.
@MainActor
@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case welcome
        case apiKey
        case microphone
        case accessibility
        case hotkey
        case test
        case ready

        var title: String {
            switch self {
            case .welcome:       return "Welcome to Murmur"
            case .apiKey:        return "OpenAI API key"
            case .microphone:    return "Microphone access"
            case .accessibility: return "Accessibility access"
            case .hotkey:        return "Pick your hotkey"
            case .test:          return "Try it out"
            case .ready:         return "You're all set"
            }
        }
    }

    /// Transient state for the test-transcription step. Lives on the model
    /// rather than the view so re-navigating back to the step shows the
    /// most recent result instead of resetting.
    enum TestState: Equatable {
        case idle
        case recording(secondsRemaining: Int)
        case transcribing
        case done(text: String)
        case failed(message: String)
    }

    // Navigation
    var step: Step = .welcome

    // Reactive permission state. Refreshed by a 1 s poll plus one-shot
    // updates after user-triggered actions (requestAccess callbacks).
    var micStatus: AVAuthorizationStatus = .notDetermined
    var axTrusted: Bool = false
    var apiKeyPresent: Bool = false

    // User-editable fields
    var apiKey: String = ""
    var apiKeyError: String?
    var hotkey: String

    // Test-transcription state
    var testState: TestState = .idle

    let config: AppConfig

    private let log = Logger(subsystem: "com.local.murmur", category: "onboarding")
    private var pollTask: Task<Void, Never>?
    private var testRecorder: Recorder?
    private var testCountdownTask: Task<Void, Never>?

    init(config: AppConfig) {
        self.config = config
        self.hotkey = config.hotkey
        refreshApiKeyPresence()
        refreshPermissions()
    }

    // MARK: Polling

    /// Called when the window appears. 1 s tick so returning from
    /// System Settings flips the corresponding step to "Granted ✓"
    /// within a second — matches freeflow's cadence.
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { self?.refreshPermissions() }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        testCountdownTask?.cancel()
        testCountdownTask = nil
    }

    private func refreshPermissions() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if mic != micStatus { micStatus = mic }
        let ax = AXIsProcessTrusted()
        if ax != axTrusted { axTrusted = ax }
    }

    private func refreshApiKeyPresence() {
        do {
            apiKeyPresent = try (Keychain.read(Keychain.openAIKey)?.isEmpty == false)
        } catch {
            log.error("Keychain read failed during onboarding: \(String(describing: error), privacy: .public)")
            apiKeyPresent = false
        }
    }

    // MARK: Actions — API key

    func saveApiKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            apiKeyError = "Paste your key, then Save."
            return
        }
        do {
            try Keychain.write(Keychain.openAIKey, value: trimmed)
            apiKey = ""                 // clear from memory once persisted
            apiKeyError = nil
            apiKeyPresent = true
            log.info("API key saved via onboarding (length=\(trimmed.count, privacy: .public))")
        } catch {
            log.error("Keychain write failed: \(String(describing: error), privacy: .public)")
            apiKeyError = "Couldn't save to Keychain — \(String(describing: error))"
        }
    }

    // MARK: Actions — Mic

    /// Triggers the system TCC prompt the first time; subsequent calls
    /// are no-ops (macOS remembers the decision). For the "denied" path
    /// the button switches to "Open System Settings" since we can't
    /// re-prompt.
    func requestMic() {
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor [weak self] in self?.refreshPermissions() }
            }
        } else {
            openMicPane()
        }
    }

    func openMicPane() {
        openSettingsPane("Privacy_Microphone")
    }

    // MARK: Actions — Accessibility

    /// Pop the system TCC prompt AND deep-link to the pane. The prompt
    /// also registers Murmur with TCC so it actually appears in the
    /// Privacy → Accessibility list (otherwise the pane opens to an
    /// empty row and users have to hunt for Murmur via "+").
    func requestAccessibility() {
        let optKey = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [optKey: kCFBooleanTrue as Any] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openSettingsPane("Privacy_Accessibility")
    }

    func openAXPane() {
        openSettingsPane("Privacy_Accessibility")
    }

    private func openSettingsPane(_ name: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(name)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Actions — Hotkey

    /// Persist the picker selection + ping AppDelegate so the live
    /// HotkeyMonitor rebinds without a relaunch. Safe to call even if
    /// the value hasn't changed (HotkeyMonitor.restart is idempotent).
    func commitHotkey() {
        guard config.hotkey != hotkey else { return }
        config.hotkey = hotkey
        NotificationCenter.default.post(name: .murmurHotkeyChanged, object: nil)
    }

    // MARK: Actions — Test transcription

    /// Kick off a 3-second record → transcribe round-trip. Surfaces
    /// API-key / model / mic issues *before* the user hits them mid-
    /// workflow, which is the whole point of this step.
    func startTest() {
        testCountdownTask?.cancel()

        guard apiKeyPresent else {
            testState = .failed(message: "Save your API key first (step 2).")
            return
        }
        guard micStatus == .authorized else {
            testState = .failed(message: "Grant Microphone access first (step 3).")
            return
        }

        let recorder = Recorder(
            sampleRate: config.sampleRate,
            channels: config.channels
        )
        do {
            try recorder.start()
        } catch RecorderError.microphoneDenied {
            testState = .failed(message: "Microphone access was revoked. Re-grant it in step 3.")
            return
        } catch {
            log.error("test recorder start failed: \(String(describing: error), privacy: .public)")
            testState = .failed(message: "Couldn't start recording.")
            return
        }
        testRecorder = recorder
        testState = .recording(secondsRemaining: 3)

        testCountdownTask = Task { [weak self] in
            for remaining in [2, 1, 0] {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self else { return }
                    if remaining > 0 {
                        self.testState = .recording(secondsRemaining: remaining)
                    }
                }
            }
            await self?.finishTest()
        }
    }

    private func finishTest() async {
        guard let recorder = testRecorder else { return }
        testRecorder = nil
        testState = .transcribing

        let wav: Data
        do {
            wav = try await recorder.stop(tailMs: 200)
        } catch {
            log.error("test recorder stop failed: \(String(describing: error), privacy: .public)")
            testState = .failed(message: "Couldn't finalize recording.")
            return
        }

        let key: String
        do {
            guard let k = try Keychain.read(Keychain.openAIKey), !k.isEmpty else {
                testState = .failed(message: "No API key saved.")
                return
            }
            key = k
        } catch {
            testState = .failed(message: "Keychain read failed.")
            return
        }

        let transcriber = Transcriber(
            apiKey: key,
            model: config.model,
            biasingPrompt: config.biasingPrompt,
            language: config.language
        )
        do {
            let text = try await transcriber.transcribe(wav: wav)
            testState = .done(text: text.isEmpty ? "(empty transcription)" : text)
        } catch let e as TranscriberError {
            testState = .failed(message: e.userMessage)
        } catch {
            log.error("test transcribe failed: \(String(describing: error), privacy: .public)")
            testState = .failed(message: "Transcription failed.")
        }
    }

    // MARK: Navigation

    /// Next is enabled when the current step has been satisfied. Welcome
    /// + hotkey + test + ready are always "passable" — the user decides
    /// when they're ready to move on.
    var canAdvance: Bool {
        switch step {
        case .welcome, .hotkey, .test, .ready: return true
        case .apiKey:        return apiKeyPresent
        case .microphone:    return micStatus == .authorized
        case .accessibility: return axTrusted
        }
    }

    func next() {
        if step == .hotkey { commitHotkey() }
        if let idx = Step.allCases.firstIndex(of: step), idx + 1 < Step.allCases.count {
            step = Step.allCases[idx + 1]
        }
    }

    func back() {
        if let idx = Step.allCases.firstIndex(of: step), idx > 0 {
            step = Step.allCases[idx - 1]
        }
    }
}

// MARK: - View

// `@MainActor` mirrors SettingsView / HistoryView — required under Swift
// 5.10 strict concurrency because the view body touches `OnboardingModel`,
// which is `@MainActor @Observable`. Without this annotation the view's
// synthesized body is treated as non-isolated and every `model.<x>` read
// becomes a hard error.
@MainActor
struct OnboardingWizardView: View {
    @Bindable var model: OnboardingModel
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                stepContent
                    .padding(.horizontal, 32)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(OnboardingModel.Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= model.step.rawValue
                              ? Color.accentColor
                              : Color.primary.opacity(0.15))
                        .frame(width: s == model.step ? 22 : 14, height: 4)
                        .animation(.easeInOut(duration: 0.18), value: model.step)
                }
            }
            Text(model.step.title)
                .font(.system(size: 18, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Back") { model.back() }
                .disabled(model.step == .welcome)
            Spacer()
            if model.step == .ready {
                Button("Finish") { onFinish() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Next") { model.next() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canAdvance)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: Step content dispatch

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome:       welcomeStep
        case .apiKey:        apiKeyStep
        case .microphone:    microphoneStep
        case .accessibility: accessibilityStep
        case .hotkey:        hotkeyStep
        case .test:          testStep
        case .ready:         readyStep
        }
    }

    // MARK: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Murmur turns your voice into text — anywhere you can paste.")
                .font(.system(size: 14))
            bullet("Press your hotkey, talk, press it again. Text appears at the cursor.")
            bullet("Lives in the menu bar — no dock icon, no windows in your way.")
            bullet("Uses OpenAI's transcription API. You provide the key, billing runs through your OpenAI account.")
            Text("The next few steps walk you through the one-time setup.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: API key

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.apiKeyPresent {
                statusRow(.ok, "API key is saved in your Keychain.")
                Text("Paste a different key to replace it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Murmur needs your OpenAI key to transcribe audio. It's stored in the macOS Keychain — never written to disk in plaintext.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            SecureField("sk-…", text: $model.apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack {
                Button("Save") { model.saveApiKey() }
                    .buttonStyle(.bordered)
                    .disabled(model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let err = model.apiKeyError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }

            Link(
                "Don't have a key? Get one at platform.openai.com/api-keys",
                destination: URL(string: "https://platform.openai.com/api-keys")!
            )
            .font(.system(size: 12))
        }
    }

    // MARK: Microphone

    private var microphoneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Murmur needs microphone access to record what you say. Audio stays local until you submit it to OpenAI for transcription.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            switch model.micStatus {
            case .authorized:
                statusRow(.ok, "Microphone access granted.")
            case .denied, .restricted:
                statusRow(.warn, "Microphone access was denied. Toggle Murmur on in System Settings → Privacy → Microphone.")
                Button("Open System Settings") { model.openMicPane() }
                    .buttonStyle(.bordered)
            case .notDetermined:
                statusRow(.pending, "Click below to grant access.")
                Button("Allow Microphone Access") { model.requestMic() }
                    .buttonStyle(.borderedProminent)
            @unknown default:
                statusRow(.warn, "Unknown microphone state — open System Settings to check.")
                Button("Open System Settings") { model.openMicPane() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Accessibility

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The global hotkey is a session-level event tap — macOS requires Accessibility permission to install it. Murmur only listens for your configured modifier key; it never logs other keystrokes.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if model.axTrusted {
                statusRow(.ok, "Accessibility access granted.")
            } else {
                statusRow(.pending, "Open System Settings and toggle Murmur on, then return here — this page will flip to ✓ automatically.")
                Button("Open Accessibility Settings") { model.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Hotkey

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tap your hotkey once to start recording. Tap again to stop and paste. Modifier-only keys work best for self-signed builds — see the hotkey doc comment if you're curious.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Picker("Hotkey", selection: $model.hotkey) {
                Text("Right Option").tag("alt_r")
                Text("Left Option").tag("alt_l")
                Text("Right Command").tag("cmd_r")
                Text("Right Control").tag("ctrl_r")
                Text("Right Shift").tag("shift_r")
            }
            .pickerStyle(.inline)
            .labelsHidden()

            Text("You can change this any time from Settings → General.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Test transcription

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Let's confirm everything works end-to-end. Click the button, say a short sentence, and Murmur will record for 3 seconds and show the transcription.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            switch model.testState {
            case .idle:
                Button("Start 3-second recording") { model.startTest() }
                    .buttonStyle(.borderedProminent)

            case .recording(let remaining):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Recording… \(remaining)s left")
                        .font(.system(size: 13))
                }

            case .transcribing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing…")
                        .font(.system(size: 13))
                }

            case .done(let text):
                VStack(alignment: .leading, spacing: 10) {
                    statusRow(.ok, "Got it:")
                    Text(text)
                        .font(.system(size: 14, design: .default))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                    Button("Record again") { model.startTest() }
                        .buttonStyle(.bordered)
                }

            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    statusRow(.warn, message)
                    Button("Try again") { model.startTest() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: Ready

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You're set. Here's how to use Murmur day-to-day:")
                .font(.system(size: 14))
            bullet("Tap your hotkey anywhere, talk, tap again — the transcribed text pastes at the cursor.")
            bullet("Click the Murmur icon in the menu bar to see History, change Settings, or re-run this help screen.")
            bullet("Everything recorded is kept in local History for \(model.config.historyRetentionDays) days by default.")
            Text("Have fun.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    // MARK: Shared chrome

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private enum StatusKind { case ok, pending, warn }

    private func statusRow(_ kind: StatusKind, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch kind {
            case .ok:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .pending:
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
            case .warn:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Window host

/// Hosts the SwiftUI wizard in a plain NSWindow. Kept out of
/// WindowManager because this one doesn't need cross-session persistence
/// and should never reopen by itself after Finish.
@MainActor
enum OnboardingWindow {
    static func make(model: OnboardingModel, onFinish: @escaping () -> Void) -> NSWindow {
        let hosting = NSHostingController(
            rootView: OnboardingWizardView(model: model, onFinish: onFinish)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Set up Murmur"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // `NSWindow.center()` horizontally centers but drops the window
        // about a third from the top — not actually centered. Compute
        // the true center off the visible frame instead so the wizard
        // sits in the middle of the active display.
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let v = screen.visibleFrame
            let size = window.frame.size
            let origin = NSPoint(
                x: v.origin.x + (v.width - size.width) / 2,
                y: v.origin.y + (v.height - size.height) / 2
            )
            window.setFrameOrigin(origin)
        }
        return window
    }
}
