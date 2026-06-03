# Releasing Murmur

Murmur ships as a **self-signed** (NOT notarized) macOS app and auto-updates via
**electron-updater** reading GitHub Releases. This doc covers how to cut a release
and — critically — how to keep users' permission grants alive across updates.

## TL;DR

1. Bump `version` in `package.json` (e.g. `2.0.0`).
2. `git tag v2.0.0 && git push origin v2.0.0`
3. CI (`.github/workflows/release.yml`) builds + signs + publishes the `.dmg`,
   `.zip`, and `latest-mac.yml` to the GitHub Release.
4. Installed copies pick it up on next launch (or via **Check for Updates…**).

## The stable signing identity (make-or-break)

Self-signed updates only work if **every release is signed by the exact same
identity**. macOS ties an app's Accessibility + Microphone (TCC) grants to its
*designated requirement*, which is derived from the signing identity. Change the
identity (or sign ad-hoc, where the CDHash changes every build) and macOS treats
the update as a *different app* → **the hotkey and paste silently stop working
until the user re-grants Accessibility.**

One-time setup:

1. Create a self-signed **code-signing** certificate (reuse the existing
   `Murmur Dev` if its private key is intact, or make a new one): Keychain Access
   → Certificate Assistant → *Create a Certificate…* → Name `Murmur Dev`, Identity
   Type **Self-Signed Root**, Certificate Type **Code Signing**.
2. Export it **with its private key** as a `.p12` (set a password).
3. Base64 it: `base64 -i murmur-dev.p12 | pbcopy`
4. Add repo secrets (Settings → Secrets and variables → Actions):
   - `MAC_CSC_LINK` = the base64 `.p12`
   - `MAC_CSC_KEY_PASSWORD` = the `.p12` password

`electron-builder` reads `CSC_LINK`/`CSC_KEY_PASSWORD`, imports the cert into a
temp keychain, and signs the app + Electron framework + every helper + the
unpacked `.node` addons with it (entitlements in `build/entitlements.mac.plist`,
hardened runtime on). **Never rotate this cert** once users are on it.

> Without the secrets, electron-builder signs **ad-hoc** (`identity: null`). That's
> fine for local test builds but produces non-persistent grants — do not publish
> ad-hoc releases.

## Local signed build (optional)

```sh
export CSC_LINK=$(base64 -i murmur-dev.p12) CSC_KEY_PASSWORD=…
npm run dist          # build:native + electron-vite build + electron-builder --mac
```

`npm run pack` (ad-hoc, `--dir`) remains the fast local-test path.

## First-launch friction (self-signed, not notarized)

Gatekeeper blocks first launch. Document for users: **right-click the app →
Open → Open**, or `xattr -dr com.apple.quarantine /Applications/Murmur.app`.

## Verification gate (do this before trusting auto-update)

The only real test of TCC persistence is **two successive signed releases on a
real machine**:

1. Install `vN`, grant Accessibility + Microphone, confirm the hotkey + paste work.
2. Publish `vN+1` (same identity), let Murmur auto-update + restart.
3. Confirm the hotkey + paste **still work without re-granting** anything.

If step 3 fails, the identity isn't stable — fix that before relying on updates.
