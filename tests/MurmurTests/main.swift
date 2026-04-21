import Foundation

// Top-level code — no @main attribute because SPM's executable target
// treats any file named `main.swift` as the script-style entry point,
// and @main conflicts with that.

@MainActor func runMainActorSuites() {
    KeychainTests.run()
    RecorderWAVTests.run()
    HotkeyKeyTests.run()
    HistoryStoreTests.run()
    AppConfigTests.run()
}

await MainActor.run { runMainActorSuites() }
await TranscriberTests.run()

exit(Harness.summary())
