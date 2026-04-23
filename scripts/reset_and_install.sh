#!/usr/bin/env bash
# Reset → rebuild → install Murmur for a clean interactive smoke test.
#
# Steps:
#   1. Kill any running Murmur instance.
#   2. Remove /Applications/Murmur.app.
#   3. Reset macOS TCC permissions for Accessibility + Microphone.
#   4. Clear the "onboarding seen" defaults flag so the welcome alert fires.
#   5. Build release bundle (scripts/build_release.sh).
#   6. Copy the fresh bundle into /Applications.
#   7. Launch it.
#
# Invoked by the dev workflow before asking the user to smoke-test onboarding
# or permission changes — see AGENTS.md "Smoke-test reset protocol".

set -euo pipefail

BUNDLE_ID="com.local.murmur"
APP_NAME="Murmur.app"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_APP="$REPO_ROOT/dist/$APP_NAME"
APPS_APP="/Applications/$APP_NAME"

echo "==> Killing any running Murmur process"
pkill -x Murmur 2>/dev/null || true
sleep 1

echo "==> Removing $APPS_APP (if present)"
rm -rf "$APPS_APP"

echo "==> Resetting TCC: Accessibility / Microphone for $BUNDLE_ID"
# Murmur uses a session-level `CGEventTap` with modifier-only hotkeys, so
# it only needs Accessibility + Microphone. Session taps silently drop
# `.keyDown` events for non-notarized apps on macOS 26 Tahoe, which is why
# we restrict to modifier keys (delivered via `.flagsChanged`, which flows
# fine). Input Monitoring would only be needed for an HID-level tap.
# The signed-with-"Murmur Dev" build has a stable Designated Requirement,
# so these grants persist across rebuilds once granted (we reset here
# only to exercise the first-run onboarding flow).
tccutil reset Accessibility "$BUNDLE_ID"  2>/dev/null || true
tccutil reset Microphone    "$BUNDLE_ID"  2>/dev/null || true

echo "==> Clearing onboardingSeen.v1 defaults flag"
defaults delete "$BUNDLE_ID" onboardingSeen.v1 2>/dev/null || true

echo "==> Building release bundle"
"$REPO_ROOT/scripts/build_release.sh"

if [[ ! -d "$DIST_APP" ]]; then
    echo "ERROR: expected $DIST_APP after build, not found" >&2
    exit 1
fi

echo "==> Copying $DIST_APP → $APPS_APP"
cp -R "$DIST_APP" "$APPS_APP"

echo "==> Launching $APPS_APP"
open "$APPS_APP"

echo
echo "Clean install ready. Walk the 10-step smoke matrix from"
echo "~/.claude/plans/noble-gliding-sedgewick.md (Verification section)."
