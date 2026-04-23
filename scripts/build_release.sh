#!/bin/bash
# Build a signed macOS .app bundle from the SPM executable.
#
#   swift build -c release   → binary at .build/release/Murmur
#   bundle                   → dist/Murmur.app/Contents/{MacOS,Resources,Info.plist}
#   codesign --sign "Murmur Dev" --options runtime
#                            → signed with a local self-signed identity +
#                              hardened runtime. Unlike ad-hoc (`--sign -`),
#                              the CDHash is derived from the identity's
#                              key material and stays stable across
#                              rebuilds, so macOS TCC grants (Accessibility,
#                              Microphone, etc.) don't invalidate every
#                              time we rebuild.
#   dmg                      → dist/Murmur-<version>.dmg for sharing.
#                              Uses `create-dmg` if available (nicer: drag
#                              target for /Applications, window layout).
#                              Falls back to a plain `hdiutil` image if
#                              not. Install locally with `brew install
#                              create-dmg`; CI installs it in release.yml.
#
# The `Murmur Dev` identity is a self-signed code-signing cert in the
# login keychain. If `security find-identity -v -p codesigning | grep
# "Murmur Dev"` returns nothing OR `codesign --sign "Murmur Dev" /tmp/foo`
# fails, regenerate with:
#
#   TMP=$(mktemp -d) && (cd "$TMP" && \
#     openssl req -x509 -nodes -newkey rsa:2048 -keyout key.pem -out cert.pem \
#       -days 3650 -subj "/CN=Murmur Dev" \
#       -addext "keyUsage = critical, digitalSignature" \
#       -addext "extendedKeyUsage = critical, codeSigning" \
#       -addext "basicConstraints = critical, CA:FALSE" && \
#     openssl pkcs12 -export -inkey key.pem -in cert.pem -name "Murmur Dev" \
#       -out id.p12 -passout pass:murmur -macalg SHA1 \
#       -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -legacy && \
#     security import id.p12 -k ~/Library/Keychains/login.keychain-db \
#       -P murmur -T /usr/bin/codesign -T /usr/bin/security)
#
# (The `-macalg SHA1 ... -legacy` flags are for OpenSSL-3 / Apple Security
# MAC compatibility — otherwise import fails with "MAC verification failed".)
#
# Usage: ./scripts/build_release.sh
#
# After building:
#   open dist/Murmur.app            # run it
#   share dist/Murmur-0.1.0.dmg     # send to a friend
#
# Friends' first launch on their Mac (because we're self-signed, not
# notarized): mount the DMG, drag Murmur.app to Applications, then
# right-click Murmur.app in /Applications → Open → Open in the dialog.
# One time per Mac. Documented in README.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

APP_NAME="Murmur"

# Resolve version:
#   - In CI on a tag push, $GITHUB_REF_NAME is "v0.2.0" → use 0.2.0
#   - Locally, fall back to `git describe` (e.g. "v0.1.0-3-gabc1234" → 0.1.0-3-gabc1234)
#   - Final fallback for a tree with no tags at all: 0.0.0-dev
if [[ -n "${GITHUB_REF_NAME:-}" && "$GITHUB_REF_NAME" == v* ]]; then
    VERSION="${GITHUB_REF_NAME#v}"
elif VERSION_FROM_GIT="$(git -C "$REPO" describe --tags --always --dirty 2>/dev/null)"; then
    VERSION="${VERSION_FROM_GIT#v}"
else
    VERSION="0.0.0-dev"
fi
echo "==> Version: $VERSION"

BUILD_DIR="$REPO/.build"
DIST_DIR="$REPO/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"
INFO_PLIST_SRC="$REPO/Resources/Info.plist"
ENTITLEMENTS="$REPO/Resources/$APP_NAME.entitlements"

echo "==> swift build -c release --product $APP_NAME"
# Build only the app product — the test target uses `@testable import` and
# would refuse to compile without -enable-testing (which we don't want in
# release).
swift build -c release --product "$APP_NAME"

BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "ERROR: expected binary at $BIN_PATH not found." >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"

# Stamp the resolved version into the bundle's Info.plist so "About Murmur",
# Finder's Get Info, and Sparkle-style update checks all agree.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Only bundle SPM resources if they exist (SwiftData migrations, xcassets,
# etc. may or may not be present depending on which milestone is building).
SPM_RESOURCES_BUNDLE="$(swift build -c release --show-bin-path)/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$SPM_RESOURCES_BUNDLE" ]]; then
    cp -R "$SPM_RESOURCES_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Murmur Dev}"
echo "==> codesign (--sign \"$CODESIGN_IDENTITY\", hardened runtime)"
# Use `find-identity` WITHOUT `-v` (and without `-p codesigning`): both of
# those filters hide self-signed identities that carry
# `CSSMERR_TP_NOT_TRUSTED`, which is expected for a self-signed root — but
# `codesign` itself is happy to use them regardless. The plain
# `find-identity` listing includes every identity in every keychain.
if ! security find-identity | grep -q "\"$CODESIGN_IDENTITY\""; then
    echo "ERROR: codesigning identity \"$CODESIGN_IDENTITY\" not found in keychain." >&2
    echo "       See the header comment in this script for how to regenerate it." >&2
    exit 1
fi
if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --timestamp=none \
        "$APP_BUNDLE"
else
    codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp=none "$APP_BUNDLE"
fi

echo "==> Verifying signature"
codesign --verify --verbose=2 "$APP_BUNDLE"

echo "==> Building DMG"
rm -f "$DMG_PATH"
# Staging dir holds exactly what ends up in the mounted volume: the .app
# plus an /Applications symlink as a drag target. Using a dedicated dir
# avoids hdiutil scooping up extra files from dist/.
DMG_STAGING="$(mktemp -d -t murmur-dmg.XXXXXX)"
trap 'rm -rf "$DMG_STAGING"' EXIT
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

if command -v create-dmg >/dev/null 2>&1; then
    # `create-dmg` writes the AppleScript-positioned window layout so the
    # user sees Murmur.app next to an Applications arrow on mount.
    # `--skip-jenkins` silences a warning about CI hostnames; harmless
    # either way.
    create-dmg \
        --volname "$APP_NAME $VERSION" \
        --window-pos 200 120 \
        --window-size 540 360 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 140 170 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 400 170 \
        --skip-jenkins \
        "$DMG_PATH" \
        "$DMG_STAGING" >/dev/null
else
    echo "    (create-dmg not found — falling back to plain hdiutil image)"
    # Add the Applications symlink manually so the drag target is still
    # present, just without the AppleScript window layout.
    ln -s /Applications "$DMG_STAGING/Applications"
    hdiutil create \
        -volname "$APP_NAME $VERSION" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        "$DMG_PATH" >/dev/null
fi

# Sign the DMG with the same identity. Not strictly required — Gatekeeper
# evaluates the app inside regardless — but it keeps `spctl --assess` happy
# on the container and costs nothing.
echo "==> codesign DMG"
codesign --force --sign "$CODESIGN_IDENTITY" --timestamp=none "$DMG_PATH"

echo
echo "Built: $APP_BUNDLE"
echo "DMG:   $DMG_PATH"
echo
echo "Launch with:   open '$APP_BUNDLE'"
echo "Share:         send $(basename "$DMG_PATH") — friends drag to /Applications, then right-click → Open on first launch."
