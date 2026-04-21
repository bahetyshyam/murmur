# Murmur

**Tap-to-talk dictation for macOS.** Press a hotkey to start recording, press it again to stop — your words appear at the cursor in whatever app you're using. Powered by OpenAI's transcription API using your own key.

- Menubar app, stays out of the way
- Default hotkey: **`⌥\`` (Option + Backtick)** — tap once to start, tap again to stop
- API key lives in the macOS Keychain — never leaves your Mac except to OpenAI
- macOS 14 Sonoma or newer, Apple Silicon or Intel

---

## Install — 60 seconds

### 1. Download

**→ [Download the latest Murmur.zip](../../releases/latest)**

(On the Releases page, grab the file named `Murmur-<version>.zip` under *Assets*.)

### 2. Unzip and move to Applications

Double-click the zip. You'll get `Murmur.app`. Drag it into your **Applications** folder.

### 3. First launch — **right-click → Open**

> This step matters. Don't double-click the first time.

In Applications, **right-click `Murmur.app` → Open**. macOS will show a warning ("Apple could not verify…") — click **Open** anyway.

<details>
<summary>Why this extra step?</summary>

Murmur is a free personal project and isn't signed with a paid Apple Developer certificate ($99/yr). Right-click → Open tells macOS you trust it. You only have to do this **once** per Mac — after that, double-click works like any other app.
</details>

### 4. Grant permissions when prompted

macOS will ask for two permissions the first time you use the app. Both are required:

- **Microphone** — so Murmur can hear you.
- **Accessibility** — so Murmur can detect the hotkey and paste text into other apps.

If you miss the prompts, open **System Settings → Privacy & Security** and enable Murmur under each section.

### 5. Paste your OpenAI API key

Click the microphone icon in your menubar → **Settings…** → paste your OpenAI API key.

Don't have one? Get it at [platform.openai.com/api-keys](https://platform.openai.com/api-keys). (A full hour of dictation costs under a dollar on `gpt-4o-transcribe`.)

---

## How to use it

1. Click into any text field, anywhere on your Mac.
2. Press **`⌥\`` (Option + Backtick)** to start recording. Speak.
3. Press **`⌥\`` again** to stop. Your transcribed text pastes at the cursor within a second or two.

That's it. The menubar icon tells you what's happening:

| Glyph | State |
|-------|-------|
| Open ring | Idle — ready for you |
| Filled dot | Recording your voice |
| Waveform | Sending to OpenAI |
| ⚠️ Yellow triangle | Something went wrong — open the menu to see the error |

If the hotkey isn't working, the menu will show **"Hotkey disabled — grant Accessibility"** with a one-click shortcut to the right System Settings pane.

---

## Updating

When a new version ships, just download the new zip, drag `Murmur.app` into Applications, and replace the old one. Your API key and settings are preserved (they live in the Keychain and `~/Library/Application Support/Murmur/`).

---

## Troubleshooting

**The hotkey doesn't do anything.**
System Settings → Privacy & Security → **Accessibility**. Make sure Murmur is listed and toggled **on**. You can also open the menubar menu → **Permissions Help…** for a guided walkthrough, or click the **"Grant Accessibility Access…"** row that appears in the menu when the hotkey is disabled.

**"Paste failed" error.**
Same place — Accessibility. Murmur needs it to simulate ⌘V. Toggle off and on if it was already enabled.

**"invalid API key".**
Menubar → Settings → API Key → paste again. Check the key is active at [platform.openai.com](https://platform.openai.com/api-keys).

**After updating, the hotkey stopped working.**
macOS ties Accessibility permission to the app's code signature, which changes with each build. In System Settings → Accessibility, remove the old Murmur entry (`−` button), add the new one (`+`), toggle on. Or run:
```bash
tccutil reset Accessibility com.local.murmur
```
…and re-grant on next launch.

**Menubar icon doesn't appear.**
Make sure you launched `Murmur.app` (not a bare binary). If it still doesn't show up, try `killall Murmur` and relaunch.

**Very short clips transcribe to empty.**
`gpt-4o-transcribe` sometimes returns nothing for <1s clips. Speak for at least a second.

---

## Settings

Menubar → **Settings…** (or ⌘,):

- **General** — model, hotkey, chime/HUD/paste toggles
- **API Key** — paste or clear the OpenAI key
- **Advanced** — biasing prompt, language, toggle-debounce, sample rate, history retention

**History** — menubar → **History…** — every transcript you've ever made, searchable, one-click copy.
Stored in `~/Library/Application Support/Murmur/history.sqlite3`.

---

## Build from source

For developers who want to build locally. Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone <this repo>
cd chatgpt-voice-to-text
./scripts/build_release.sh
open dist/Murmur.app
```

Produces `dist/Murmur.app` and `dist/Murmur-<version>.zip`.

During development:

```bash
swift build                 # debug build
swift run Murmur            # run binary directly (no bundle)
swift run MurmurTests       # test harness
```

### Cutting a release

Releases are built by GitHub Actions (`.github/workflows/release.yml`):

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds `Murmur.app` on a `macos-14` runner, zips it, and attaches the zip to a new GitHub Release. You can also trigger a manual build from the **Actions** tab (uploads a zip artifact without cutting a release).

---

## Why not notarized / on the App Store?

Notarization needs a paid Apple Developer account ($99/yr). App Store distribution needs sandboxing, which blocks the global hotkey and paste behavior that make this app useful. Ad-hoc signing is the honest compromise for a personal tool.

If you do have a Developer ID, swap `codesign --sign -` in `scripts/build_release.sh` for your identity, run `xcrun notarytool submit`, and `xcrun stapler staple`. Everything else stays the same.

---

## License

MIT.
