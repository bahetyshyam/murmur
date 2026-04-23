# AGENTS.md — development conventions for Murmur

Guidance for AI coding agents (and humans) working in this repo.

## Reset-and-install protocol (MANDATORY before every test handoff)

**Any time you ask the user to test a Murmur build — whether it's a smoke
test, a bug-repro, a one-off "does this fix it?" check, a bisect step, or
anything else — the build handed to them MUST come from
`./scripts/reset_and_install.sh`. No exceptions.**

This applies to:
- Testing uncommitted changes.
- Testing a committed version (e.g. bisecting regressions).
- Re-testing after the user reports a failure.
- Any build you would otherwise produce with `scripts/build_release.sh`
  alone — **do not `open dist/Murmur.app` or `cp` into Applications and
  hand it off; always go through `reset_and_install.sh`**.

Do **not** call `scripts/build_release.sh` directly as the last step
before a test. `reset_and_install.sh` already invokes it internally; use
the wrapper.

The script:

1. Kills any running `Murmur` process.
2. Deletes `/Applications/Murmur.app`.
3. Resets TCC for Accessibility and Microphone (`com.local.murmur`).
   Session-level CGEventTaps silently drop `.keyDown` events from
   non-notarized apps on macOS 26 Tahoe, so Murmur restricts its hotkey
   to modifier-only keys (delivered via `.flagsChanged`, which flows
   fine for self-signed session taps). No Input Monitoring grant needed.
4. Clears the `onboardingSeen.v1` defaults flag so the welcome alert fires.
5. Builds the release bundle via `scripts/build_release.sh`.
6. Copies the bundle into `/Applications`.
7. Launches it.

**Only skip this** if the user explicitly says "don't reset" in that
message. Even tests framed as "returning user" go through the reset —
resetting then granting fresh is the same outcome and avoids stale-grant
bugs that mask regressions.

## Build / test

- `swift build` — compile.
- `swift run MurmurTests` — test (see `Package.swift` for why tests are an
  executable target rather than XCTest).
- `scripts/build_release.sh` — produce `dist/Murmur.app` (ad-hoc signed).
- `scripts/reset_and_install.sh` — full reset + install to `/Applications`.
