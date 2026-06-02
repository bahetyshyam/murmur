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
# --- Sparkle update signing (EdDSA) ----------------------------------------
# This script embeds Sparkle.framework and generates an EdDSA-signed
# appcast.xml. Signing needs the private key created once with:
#
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys
#
# which stores the key in your login keychain and prints the SUPublicEDKey to
# paste into Resources/Info.plist. Locally, generate_appcast reads the key from
# the keychain automatically. For CI, export it once:
#
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_priv.txt
#
# and store the file's contents as the SPARKLE_ED_PRIVATE_KEY GitHub secret
# (this script reads that env var and passes it via --ed-key-file). The public
# key in Info.plist and the private key MUST stay paired — losing the private
# key means existing installs can no longer verify (and thus can't accept)
# updates.
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

# --- Generate the app icon (.icns) ------------------------------------------
# The Ink-dot app icon is drawn in pure code (DesignSystemCore.InkIcon). Render
# an iconset via the DMGAssets tool and pack it with iconutil so Finder, the
# Dock, Get Info, and the DMG show the real icon instead of a generic
# placeholder. Info.plist declares CFBundleIconFile=Murmur. Must run BEFORE
# codesign so the .icns is sealed into the bundle. Non-fatal on failure.
echo "==> Generating app icon (.icns)"
swift build -c release --product DMGAssets >/dev/null
DMGASSETS_BIN="$(swift build -c release --show-bin-path)/DMGAssets"
ICON_TMP="$(mktemp -d -t murmur-icon.XXXXXX)"
ICONSET="$ICON_TMP/Murmur.iconset"
mkdir -p "$ICONSET"
# arg1 (bg png) is required by the tool but unused here; arg2 is the iconset dir.
if "$DMGASSETS_BIN" "$ICON_TMP/_unused.png" "$ICONSET" \
   && [[ -f "$ICONSET/icon_512x512.png" ]] \
   && iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/Murmur.icns"; then
    echo "    Murmur.icns → Contents/Resources"
else
    echo "    (icon generation failed — bundling without .icns; Finder shows a placeholder)"
fi
rm -rf "$ICON_TMP"

# --- Embed Sparkle.framework ------------------------------------------------
# `swift build` links Sparkle but — unlike Xcode's "Embed Frameworks" phase —
# does not copy the framework into the bundle. Locate the universal
# (arm64+x86_64) framework from the resolved SPM binary artifact and copy it
# into Contents/Frameworks. The executable already carries an
# `@executable_path/../Frameworks` rpath (see Package.swift) so it resolves
# the dylib at runtime.
echo "==> Embedding Sparkle.framework"
SPARKLE_FRAMEWORK="$(find "$BUILD_DIR/artifacts" -type d -name 'Sparkle.framework' -path '*macos-arm64_x86_64*' 2>/dev/null | head -1)"
if [[ -z "$SPARKLE_FRAMEWORK" || ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "ERROR: Sparkle.framework not found under $BUILD_DIR/artifacts." >&2
    echo "       Run 'swift build' (or 'swift package resolve') first." >&2
    exit 1
fi
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
# `-R` preserves the Versions/Current symlink structure that codesign requires.
cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"
DEST_FW="$FRAMEWORKS_DIR/Sparkle.framework"

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

# Sparkle must be signed inside-out (nested helpers first, framework last)
# with the SAME identity as the app. Hardened runtime (`--options runtime`)
# turns on library validation, which refuses to load a framework signed by a
# different team — re-signing with our identity is what makes the dylib
# loadable. We're not sandboxed, so the nested helpers need no entitlements.
echo "==> codesign Sparkle.framework (inside-out, \"$CODESIGN_IDENTITY\")"
SPARKLE_VDIR="$(/bin/ls "$DEST_FW/Versions" | grep -v Current | head -1)"
SPARKLE_INNER="$DEST_FW/Versions/$SPARKLE_VDIR"
for component in \
    "$SPARKLE_INNER/XPCServices/Downloader.xpc" \
    "$SPARKLE_INNER/XPCServices/Installer.xpc" \
    "$SPARKLE_INNER/Updater.app" \
    "$SPARKLE_INNER/Autoupdate"; do
    if [[ -e "$component" ]]; then
        codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp=none "$component"
    fi
done
codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp=none "$DEST_FW"

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
# --deep --strict so a mis-signed nested Sparkle component (XPC service,
# Updater.app, Autoupdate, or the framework itself) fails the build here
# rather than silently at the user's first update.
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Building DMG"
rm -f "$DMG_PATH"
# Staging dir holds exactly what ends up in the mounted volume: the .app
# plus an /Applications symlink as a drag target. Using a dedicated dir
# avoids hdiutil scooping up extra files from dist/.
DMG_STAGING="$(mktemp -d -t murmur-dmg.XXXXXX)"
DMG_BG_DIR="$(mktemp -d -t murmur-dmgbg.XXXXXX)"
trap 'rm -rf "$DMG_STAGING" "$DMG_BG_DIR"' EXIT
cp -R "$APP_BUNDLE" "$DMG_STAGING/"

# Render the on-brand DMG background (cream canvas, serif headline, gold arrow)
# via the DMGAssets tool — it reuses DesignSystemCore's Ink palette / serif font
# / arrow geometry without linking Sparkle. If the render fails (e.g. a headless
# CI quirk), fall back to create-dmg's plain layout rather than breaking the build.
echo "==> Rendering DMG background"
swift build -c release --product DMGAssets >/dev/null
DMG_BG="$DMG_BG_DIR/background.png"
DMG_BG_ARGS=()
if "$(swift build -c release --show-bin-path)/DMGAssets" "$DMG_BG" && [[ -f "$DMG_BG" ]]; then
    DMG_BG_ARGS=(--background "$DMG_BG")
else
    echo "    (DMG background render failed — using create-dmg's plain layout)"
fi

if command -v create-dmg >/dev/null 2>&1; then
    # `create-dmg` runs an AppleScript that tells Finder to apply the window
    # size, background image, and icon positions, persisting them as the
    # volume's .DS_Store. Do NOT pass `--skip-jenkins`: despite the name, it
    # *skips that AppleScript entirely*, producing a plain unstyled window with
    # no background — see create-dmg issue #72. The AppleScript needs a GUI
    # session + Finder automation (fine locally and on GitHub's macOS runners,
    # which have a logged-in session).
    # `${ARR[@]+"${ARR[@]}"}` is the bash-3.2-safe empty-array expansion.
    # Window height bumped 360→380 to give the headline room above the icons.
    create-dmg \
        --volname "$APP_NAME $VERSION" \
        --window-pos 200 120 \
        --window-size 540 380 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 140 170 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 400 170 \
        ${DMG_BG_ARGS[@]+"${DMG_BG_ARGS[@]}"} \
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

# --- Generate the Sparkle appcast -------------------------------------------
# Sparkle reads `appcast.xml` (published as a release asset, reachable at the
# stable `releases/latest/download/appcast.xml`) to learn about new versions.
# `generate_appcast` mounts the DMG, reads the bundle version, computes the
# EdDSA signature, and writes the feed. We run it over a clean staging dir
# holding only THIS build's DMG so the feed lists a single item whose
# enclosure points at this release's asset (download-url-prefix below).
echo "==> Generating appcast.xml"
GENERATE_APPCAST="$(find "$BUILD_DIR/artifacts" -type f -name generate_appcast -path '*Sparkle*' 2>/dev/null | head -1)"
if [[ -z "$GENERATE_APPCAST" ]]; then
    echo "ERROR: generate_appcast not found under $BUILD_DIR/artifacts." >&2
    exit 1
fi

APPCAST_STAGING="$(mktemp -d -t murmur-appcast.XXXXXX)"
trap 'rm -rf "$DMG_STAGING" "$DMG_BG_DIR" "$APPCAST_STAGING" "${ED_KEY_FILE:-}"' EXIT
cp "$DMG_PATH" "$APPCAST_STAGING/"

DOWNLOAD_PREFIX="https://github.com/bahetyshyam/murmur/releases/download/v${VERSION}/"

# EdDSA private key: locally read from the login keychain (created once via
# `generate_keys`); in CI, provide it through the SPARKLE_ED_PRIVATE_KEY env
# var (the key string exported by `generate_keys -x`).
ED_KEY_ARGS=()
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    ED_KEY_FILE="$(mktemp)"
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$ED_KEY_FILE"
    ED_KEY_ARGS=(--ed-key-file "$ED_KEY_FILE")
fi

# `${ARR[@]+"${ARR[@]}"}` guards against macOS's bash 3.2 treating an empty
# array expansion as an unbound variable under `set -u`.
"$GENERATE_APPCAST" \
    ${ED_KEY_ARGS[@]+"${ED_KEY_ARGS[@]}"} \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    --link "https://github.com/bahetyshyam/murmur" \
    "$APPCAST_STAGING"

cp "$APPCAST_STAGING/appcast.xml" "$DIST_DIR/appcast.xml"

echo
echo "Built:   $APP_BUNDLE"
echo "DMG:     $DMG_PATH"
echo "Appcast: $DIST_DIR/appcast.xml"
echo
echo "Launch with:   open '$APP_BUNDLE'"
echo "Share:         send $(basename "$DMG_PATH") — friends drag to /Applications, then right-click → Open on first launch."
