import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted to jump the live Settings window to a specific tab.
    /// The `object` is a `SettingsView.Tab`.
    static let murmurSelectSettingsTab = Notification.Name("com.local.murmur.selectSettingsTab")

    /// Posted after Settings writes a new `config.hotkey`. AppDelegate
    /// rebuilds the HotkeyMonitor so the change takes effect without a
    /// relaunch.
    static let murmurHotkeyChanged = Notification.Name("com.local.murmur.hotkeyChanged")
}

/// Native Preferences window. Tabs: General / API Key / Advanced.
///
/// Layout mirrors the Tahoe design mock in
/// `murmur/project/settings-window.jsx`: 520×400, 130pt right-aligned label
/// column, control + plain-language caption stacked on the right, thin
/// dividers aligned with the control column.
@MainActor
struct SettingsView: View {
    /// Which preferences tab is visible. Exposed so other parts of the app
    /// (e.g. the "add your API key" launch prompt) can route the user
    /// straight to the right pane.
    enum Tab: String, Hashable {
        case general, apiKey, usage, advanced
    }

    let config: AppConfig
    let history: HistoryStore
    @State private var apiKey: String = ""
    @State private var apiKeyStatus: String = ""
    @State private var hotkey: String
    @State private var selectedTab: Tab
    /// Snapshot of the usage aggregate so the tab renders synchronously.
    /// Refreshed whenever the Usage tab is selected — SQL aggregate is
    /// fast enough (sub-ms on N=thousands) that we don't need a cache.
    @State private var usageRows: [HistoryStore.UsageRow] = []

    init(config: AppConfig, history: HistoryStore, initialTab: Tab = .general) {
        self.config = config
        self.history = history
        self._hotkey = State(initialValue: config.hotkey)
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            general
                .tabItem { Label("General", systemImage: "gear") }
                .tag(Tab.general)
            apiKeyTab
                .tabItem { Label("API Key", systemImage: "key") }
                .tag(Tab.apiKey)
            usageTab
                .tabItem { Label("Usage", systemImage: "dollarsign.circle") }
                .tag(Tab.usage)
            advanced
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
                .tag(Tab.advanced)
        }
        // Breathing room between the macOS titlebar and the tab segmented
        // control, and a bit extra at the sides/bottom so tab content doesn't
        // butt up against the window chrome. The mock's tab bar has
        // `padding: '10px 12px 12px'` — this matches it.
        .padding(.top, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        // Preferred size, but resizable so long content (e.g. Usage
        // history once we start adding rows) scrolls gracefully.
        .frame(minWidth: 520, idealWidth: 520, minHeight: 400, idealHeight: 400)
        .onAppear {
            loadApiKey()
            refreshUsage()
        }
        .onChange(of: selectedTab) { _, new in
            // Re-read so numbers are fresh each time the tab opens —
            // the window stays alive across menu clicks, so a stale
            // snapshot would otherwise persist indefinitely.
            if new == .usage { refreshUsage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .murmurSelectSettingsTab)) { note in
            if let tab = note.object as? Tab {
                selectedTab = tab
            }
        }
    }

    // MARK: - General

    private var general: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            SettingRow(
                label: "Model",
                caption: "Faster = cheaper. gpt-4o-transcribe is the best all-rounder."
            ) {
                Picker("", selection: Binding(
                    get: { config.model },
                    set: { config.model = $0 }
                )) {
                    Text("gpt-4o-transcribe").tag("gpt-4o-transcribe")
                    Text("gpt-4o-mini-transcribe").tag("gpt-4o-mini-transcribe")
                    Text("whisper-1").tag("whisper-1")
                }
                .labelsHidden()
                .frame(width: 210)
            }

            SettingRow(
                label: "Hotkey",
                caption: "Tap a modifier key to start recording, tap again to stop."
            ) {
                // Modifier-only hotkeys. Chord hotkeys (⌥`, ⌘⇧Space, …) are
                // not offered because their .keyDown events get silently
                // dropped by macOS 26 session taps in non-notarized apps —
                // see HotkeyMonitor doc comment.
                Picker("", selection: $hotkey) {
                    Text("Right Option").tag("alt_r")
                    Text("Left Option").tag("alt_l")
                    Text("Right Command").tag("cmd_r")
                    Text("Right Control").tag("ctrl_r")
                    Text("Right Shift").tag("shift_r")
                }
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: hotkey) { _, new in
                    config.hotkey = new
                    NotificationCenter.default.post(
                        name: .murmurHotkeyChanged, object: nil
                    )
                }
            }

            InlineDivider()

            ToggleRow(
                label: "Play start/end chimes",
                caption: "Soft tick when recording starts and stops.",
                isOn: Binding(
                    get: { config.chimesEnabled },
                    set: { config.chimesEnabled = $0 }
                )
            )
            ToggleRow(
                label: "Show HUD while recording",
                caption: "Overlay so you know Murmur is listening.",
                isOn: Binding(
                    get: { config.hudEnabled },
                    set: { config.hudEnabled = $0 }
                )
            )
            ToggleRow(
                label: "Paste at cursor",
                caption: "Off = copy to clipboard only.",
                isOn: Binding(
                    get: { config.pasteAtCursor },
                    set: { config.pasteAtCursor = $0 }
                )
            )
            ToggleRow(
                label: "Restore clipboard after paste",
                caption: "Put your previous clipboard back afterward.",
                isOn: Binding(
                    get: { config.restoreClipboard },
                    set: { config.restoreClipboard = $0 }
                )
            )
        }
        .padding(EdgeInsets(top: 16, leading: 22, bottom: 14, trailing: 22))
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }

    // MARK: - API Key

    private var apiKeyTab: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("OpenAI API Key")
                    .font(.system(size: 17, weight: .semibold))
                Text("Stored securely in macOS Keychain. Never written to disk.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            SecureField("sk-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            HStack(spacing: 8) {
                Button("Save") { saveApiKey() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                Button("Clear") { clearApiKey() }
                    .tint(.red)
                Spacer()
                Text(apiKeyStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.top, 2)

            (Text("Don't have a key? Get one at ")
                + Text("platform.openai.com/api-keys").foregroundColor(.accentColor)
                + Text(". You'll be billed by OpenAI based on how much audio you record — typically a fraction of a cent per minute."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }

    // MARK: - Usage

    /// "Estimated spend" tab. OpenAI's transcription endpoint doesn't
    /// return token usage, so we estimate from audio duration × the
    /// public per-minute price per model. Numbers come from History —
    /// which means the window mirrors `historyRetentionDays` (default 30).
    private var usageTab: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Estimated spend")
                    .font(.system(size: 17, weight: .semibold))
                Text(usageCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatUSD(totalEstimatedCost))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            if usageRows.isEmpty {
                HStack {
                    Spacer()
                    Text("No transcriptions yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    usageHeaderRow
                    Divider()
                    ForEach(usageRows, id: \.model) { row in
                        usageRowView(row)
                        Divider()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }

    private var usageCaption: String {
        let days = config.historyRetentionDays
        let scope = days > 0
            ? "Covers the last \(days) day\(days == 1 ? "" : "s") of history — older rows are pruned per your retention setting."
            : "Covers your full history (retention is set to keep everything)."
        return "Estimated from audio duration × OpenAI's published per-minute pricing. \(scope)"
    }

    private var totalEstimatedCost: Double {
        usageRows.reduce(0) { $0 + HistoryStore.estimatedCost(for: $1) }
    }

    private var usageHeaderRow: some View {
        HStack {
            Text("Model")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Count")
                .frame(width: 60, alignment: .trailing)
            Text("Minutes")
                .frame(width: 80, alignment: .trailing)
            Text("Cost")
                .frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func usageRowView(_ row: HistoryStore.UsageRow) -> some View {
        HStack {
            Text(row.model)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.count)")
                .font(.system(size: 12))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
            Text(formatMinutes(row.totalSeconds))
                .font(.system(size: 12))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Text(formatUSD(HistoryStore.estimatedCost(for: row)))
                .font(.system(size: 12))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func refreshUsage() {
        usageRows = history.usageByModel()
    }

    private func formatUSD(_ value: Double) -> String {
        // Costs are typically fractions of a cent per transcription, so
        // four decimal places is the minimum useful precision.
        String(format: "$%.4f", value)
    }

    private func formatMinutes(_ seconds: Double) -> String {
        String(format: "%.1f", seconds / 60.0)
    }

    // MARK: - Advanced

    private var advanced: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            SettingRow(
                label: "Vocabulary hint",
                caption: "Words Murmur should get right — names, jargon, acronyms."
            ) {
                TextField("", text: Binding(
                    get: { config.biasingPrompt },
                    set: { config.biasingPrompt = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            SettingRow(
                label: "Language",
                caption: "Two-letter code like \u{201C}en.\u{201D} Leave empty to auto-detect."
            ) {
                TextField("", text: Binding(
                    get: { config.language },
                    set: { config.language = $0 }
                ), prompt: Text("auto"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            }

            InlineDivider()

            SettingRow(
                label: "Release tail",
                caption: "Keep listening briefly after release so sentence endings aren't cut off."
            ) {
                numericStepper(
                    value: Binding(
                        get: { config.releaseTailMs },
                        set: { config.releaseTailMs = $0 }
                    ),
                    range: 0...1000,
                    step: 50,
                    unit: "ms"
                )
            }

            SettingRow(
                label: "Debounce",
                caption: "Ignore repeat toggles faster than this."
            ) {
                numericStepper(
                    value: Binding(
                        get: { Int(config.minPressDurationS * 1000) },
                        set: { config.minPressDurationS = Double($0) / 1000 }
                    ),
                    range: 0...1000,
                    step: 50,
                    unit: "ms"
                )
            }

            SettingRow(
                label: "Keep history",
                caption: "How long past transcriptions stay on your Mac. 0 = forever."
            ) {
                numericStepper(
                    value: Binding(
                        get: { config.historyRetentionDays },
                        set: { config.historyRetentionDays = $0 }
                    ),
                    range: 0...365,
                    step: 1,
                    unit: "days"
                )
            }
        }
        .padding(EdgeInsets(top: 16, leading: 22, bottom: 14, trailing: 22))
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }

    @ViewBuilder
    private func numericStepper(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        unit: String
    ) -> some View {
        HStack(spacing: 6) {
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
            Text(unit)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - API key persistence

    private func loadApiKey() {
        do {
            apiKey = (try Keychain.read(Keychain.openAIKey)) ?? ""
            apiKeyStatus = apiKey.isEmpty ? "No key set." : "Loaded from Keychain."
        } catch {
            apiKey = ""
            apiKeyStatus = "Keychain error: \(error)"
        }
    }

    private func saveApiKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            apiKeyStatus = "Key is empty — nothing saved."
            return
        }
        do {
            try Keychain.write(Keychain.openAIKey, value: trimmed)
            apiKeyStatus = "Saved to Keychain."
        } catch {
            apiKeyStatus = "Save failed: \(error)"
        }
    }

    private func clearApiKey() {
        do {
            try Keychain.delete(Keychain.openAIKey)
            apiKey = ""
            apiKeyStatus = "Cleared from Keychain."
        } catch {
            apiKeyStatus = "Clear failed: \(error)"
        }
    }
}

// MARK: - Row atoms (mirror settings-window.jsx FormRow)

/// Right-aligned 130pt label + left-aligned control stack with caption.
/// Matches `FormRow` in the design mock.
private struct SettingRow<Control: View>: View {
    let label: String
    let caption: String?
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 130, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    control()
                    Spacer(minLength: 0)
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Toggle row: empty label column, switch + trailing text, caption underneath.
/// Matches the JSX toggle rows where `label=""` and the label text sits after
/// the switch.
private struct ToggleRow: View {
    let label: String
    let caption: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Keep the 130pt column so toggles align with the popup column above.
            Color.clear.frame(width: 130, height: 1)
            VStack(alignment: .leading, spacing: 3) {
                Toggle(isOn: $isOn) {
                    Text(label).font(.system(size: 13))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 0.5pt divider aligned with the control column (inset from the label column),
/// mirroring the mock's `margin: '2px 0 2px 140px'` rule.
private struct InlineDivider: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 140, height: 0.5)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
        }
        .padding(.vertical, 2)
    }
}

