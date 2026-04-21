#!/bin/bash
# Build a signed macOS .app bundle from the SPM executable.
#
#   swift build -c release   → binary at .build/release/Murmur
#   bundle                   → dist/Murmur.app/Contents/{MacOS,Resources,Info.plist}
#   codesign --sign -        → ad-hoc signature (no $99/yr Apple Dev account)
#   zip                      → dist/Murmur-<version>.zip for sharing
#
# Usage: ./scripts/build_release.sh
#
# After building:
#   open dist/Murmur.app            # run it
#   share dist/Murmur-0.1.0.zip     # send to a friend
#
# Friends' first launch on their Mac (because we're ad-hoc signed, not
# notarized):  right-click Murmur.app → Open → Open in the dialog.
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
ZIP_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.zip"
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

echo "==> codesign (ad-hoc)"
if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --sign - \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --timestamp=none \
        "$APP_BUNDLE"
else
    codesign --force --sign - --options runtime --timestamp=none "$APP_BUNDLE"
fi

echo "==> Verifying signature"
codesign --verify --verbose=2 "$APP_BUNDLE"

echo "==> Zipping for share"
rm -f "$ZIP_PATH"
( cd "$DIST_DIR" && zip -qr "$(basename "$ZIP_PATH")" "$APP_NAME.app" )

echo
echo "Built: $APP_BUNDLE"
echo "Zip:   $ZIP_PATH"
echo
echo "Launch with:   open '$APP_BUNDLE'"
echo "Share:         send $(basename "$ZIP_PATH") — friends unzip + right-click → Open on first launch."
