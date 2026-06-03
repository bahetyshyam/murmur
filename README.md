# Murmur

**Tap-to-talk dictation for macOS.** Tap a key to start recording, tap it again to stop — your words appear at the cursor in whatever app you're using. Powered by OpenAI's transcription API using your own key.

- Lives in the **menu bar and Dock**, stays out of the way
- Default hotkey: **tap Right Option (⌥)** — tap once to start, tap again to stop (configurable in Settings)
- API key lives in the macOS Keychain — never leaves your Mac except to OpenAI
- macOS 14+ (Sonoma or newer), Apple Silicon

---

## Install — 60 seconds

### 1. Download

**→ [Download the latest release](../../releases/latest)**

On the Releases page, under *Assets*, grab **`Murmur-<version>-arm64.dmg`**.

### 2. Drag to Applications

Open the `.dmg` and drag **Murmur** onto the **Applications** shortcut.

### 3. First launch — get past the "could not verify" warning

Murmur is self-signed (not notarized), so the first launch needs one extra step. In **Applications**, **right-click `Murmur` → Open**, then click **Open** in the dialog.

<details>
<summary>Prefer the Terminal? One command.</summary>

```bash
xattr -dr com.apple.quarantine /Applications/Murmur.app
```

Removes the "downloaded from the internet" flag that triggers Gatekeeper, after which `Murmur` opens with a normal double-click.
</details>

### 4. Set up

On first launch Murmur opens a short **setup wizard**: paste your OpenAI API key, grant **Microphone** and **Accessibility** access (both required — for hearing you and for the global hotkey + paste), and pick your hotkey. You can re-run it anytime from the Dock/menu-bar menu → **Set up Murmur…**.

Don't have a key? Get one at [platform.openai.com/api-keys](https://platform.openai.com/api-keys). (A full hour of dictation costs under a dollar on `gpt-4o-transcribe`.)

---

## How to use it

1. Click into any text field, anywhere on your Mac.
2. **Tap Right Option (⌥)** to start recording. Speak.
3. **Tap it again** to stop. Your transcribed text pastes at the cursor within a second or two.

A small HUD pill appears near the bottom of the screen while you're recording (live level) and transcribing (spinner). The menu-bar glyph mirrors the state: open ring (idle), filled dot (recording), waveform (transcribing).

> **Reaching the app:** click the **Murmur Dock icon** to open Settings (right-click it for History, Permissions Help, etc.). On macOS 26 "Tahoe" the menu-bar icon may be hidden by a known OS bug that drops third-party menu-bar items — the **Dock icon is the reliable entry point**.

---

## Updating

**Murmur updates itself** via GitHub Releases — it checks in the background and on launch, and prompts you to restart when a new version is ready.

- Check right now: Dock/menu-bar menu → **Check for Updates…**
- Stay put: Settings → General → turn off **Automatically check for updates**.

Your API key, settings, and history are preserved across updates (Keychain + `~/Library/Application Support/Murmur/`).

> Builds are **self-signed**. If a future release is signed with a different identity than the one you installed, macOS may ask you to re-grant **Accessibility** once after the update. See [`RELEASING.md`](RELEASING.md) for how releases keep that grant stable.

---

## Troubleshooting

**The hotkey doesn't do anything.**
System Settings → Privacy & Security → **Accessibility** — make sure Murmur is listed and toggled **on**. Or use the Dock/menu-bar menu → **Permissions Help…** for a guided walkthrough.

**"Paste failed — text is on the clipboard."**
Same place — Accessibility (Murmur needs it to simulate ⌘V). The text is safely on your clipboard; just paste it. Toggle Accessibility off/on if it was already enabled.

**"API key invalid — open Settings."**
Dock icon → Settings → General → re-paste the key. Confirm it's active at [platform.openai.com](https://platform.openai.com/api-keys).

**After updating, the hotkey stopped working.**
macOS ties Accessibility to the app's signature. In System Settings → Accessibility, remove the old Murmur entry (`−`), add the new one (`+`), toggle on. Or:
```bash
tccutil reset Accessibility com.murmur.app
```
…and re-grant on next launch.

**Very short clips transcribe to empty / nonsense.**
`gpt-4o-transcribe` can hallucinate on silence or <1s clips. Speak for at least a second; Murmur also skips clips that never rise above background level.

---

## Settings

Click the Dock icon (or menu bar → **Settings…**, ⌘,):

- **General** — OpenAI key, model (`gpt-4o-transcribe` / `gpt-4o-mini-transcribe` / `whisper-1`), microphone, record-test, hotkey, paste-at-cursor, automatic updates.
- **History** — every transcript, with one-click copy and delete. Stored in `~/Library/Application Support/Murmur/history.sqlite3`.
- **Usage** — estimated spend per model (audio minutes × OpenAI's per-minute pricing).

---

## Build from source

Requires macOS 14+, Node 20+, and Xcode Command Line Tools (`xcode-select --install`) for the native addon.

```bash
git clone https://github.com/bahetyshyam/murmur
cd murmur
npm install
npm run pack          # build native modules + bundle + package an unsigned .app under release/
open release/mac-arm64/Murmur.app
```

During development the renderer/HMR runs with `npm run dev`, but the tray, Dock, global hotkey, and native paste **only work in the packaged app** (`npm run pack`) — test those there.

Stack: **Electron + React + TypeScript** (electron-vite + electron-builder), a native N-API **CGEventTap** addon for the global modifier hotkey + synthetic paste, `better-sqlite3` for history, and `safeStorage` (Keychain) for the API key.

### Cutting a release

```bash
# bump "version" in package.json, then:
git tag v2.0.1
git push origin v2.0.1
```

GitHub Actions (`.github/workflows/release.yml`) builds on a `macos-14` runner and runs `electron-builder --mac --publish`, attaching the `.dmg`, `.zip`, and `latest-mac.yml` (the electron-updater feed) to a GitHub Release. **electron-builder creates the release as a _draft_** — open it on the Releases page and click **Publish release** to make it live (and the new "Latest"). See [`RELEASING.md`](RELEASING.md) for the self-signed code-signing identity (the `MAC_CSC_*` secrets) that keeps Accessibility/microphone grants alive across updates.

---

## Why not notarized / on the App Store?

Notarization needs a paid Apple Developer account ($99/yr). App Store distribution requires sandboxing, which blocks the global hotkey and paste that make this app useful. Self-signed is the honest compromise for a personal tool.

---

## License

MIT.
