#!/bin/bash
# macos/scripts/build.sh — build Odysseus.app (and Odysseus.dmg) for macOS.
#
# Produces a genuine native app: a SwiftUI/AppKit shell (macos/app) that
# spawns and supervises a PyInstaller-frozen copy of the backend
# (macos/backend) and shows it in an embedded WKWebView — not the thin
# browser-launcher the repo-root build-macos-app.sh produces.
#
# Usage:
#   ./macos/scripts/build.sh
#
# Prerequisites:
#   - Xcode command line tools (swift, xcrun) installed.
#   - A Python environment with `pip install -r requirements.txt pyinstaller`
#     already run (activate it before calling this script, or point
#     PYINSTALLER_BIN at a specific pyinstaller binary).
#
# Signing:
#   Ad-hoc by default — builds and runs locally with zero setup, for any
#   contributor or CI. For a real Developer ID + notarized build, set (e.g.
#   in a gitignored macos/Local.env, sourced automatically if present):
#     CODESIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#     NOTARIZE_PROFILE     name of a keychain profile created via
#                           `xcrun notarytool store-credentials`
#   Apple ID / Team ID / notarization credentials are yours to set up
#   (Xcode → Settings → Accounts, or `xcrun notarytool store-credentials`)
#   — this script only picks up what's already configured, it doesn't handle
#   your credentials itself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACOS_DIR="$ROOT/macos"
BACKEND_DIR="$MACOS_DIR/backend"
APP_SRC_DIR="$MACOS_DIR/app"
DIST="$MACOS_DIR/dist"
APP_NAME="Odysseus"
APP_BUNDLE="$DIST/$APP_NAME.app"

if [ -f "$MACOS_DIR/Local.env" ]; then
  # shellcheck disable=SC1091
  source "$MACOS_DIR/Local.env"
fi
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"  # "-" = ad-hoc

echo "==> Building $APP_NAME.app"
echo "    signing identity: $CODESIGN_IDENTITY"

rm -rf "$DIST"
mkdir -p "$DIST"

# ── 1. Freeze the backend ──────────────────────────────────────────────
echo "--> Freezing backend with PyInstaller"
PYINSTALLER_BIN="${PYINSTALLER_BIN:-pyinstaller}"
if ! command -v "$PYINSTALLER_BIN" >/dev/null 2>&1; then
  echo "error: pyinstaller not found. Activate a Python env with"
  echo "       'pip install -r requirements.txt pyinstaller' first, or set PYINSTALLER_BIN." >&2
  exit 1
fi
(
  cd "$ROOT"
  "$PYINSTALLER_BIN" --noconfirm \
    --distpath "$BACKEND_DIR/dist" \
    --workpath "$BACKEND_DIR/build" \
    "$BACKEND_DIR/Odysseus-macos.spec"
)

BACKEND_OUT="$BACKEND_DIR/dist/$APP_NAME"
if [ ! -x "$BACKEND_OUT/$APP_NAME" ]; then
  echo "error: expected frozen backend at $BACKEND_OUT/$APP_NAME, not found." >&2
  exit 1
fi

# ── 2. Build the Swift shell ───────────────────────────────────────────
echo "--> Building native shell (swift build -c release)"
( cd "$APP_SRC_DIR" && swift build -c release )
SWIFT_BIN="$APP_SRC_DIR/.build/release/$APP_NAME"
if [ ! -x "$SWIFT_BIN" ]; then
  echo "error: expected Swift binary at $SWIFT_BIN, not found." >&2
  exit 1
fi

# ── 3. Assemble the .app bundle ────────────────────────────────────────
echo "--> Assembling $APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/backend"
cp "$SWIFT_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp -R "$BACKEND_OUT/." "$APP_BUNDLE/Contents/Resources/backend/"

# Icon (static/icons/icon-512.png is already a square PWA icon — no crop needed).
ICON_SRC="$ROOT/static/icons/icon-512.png"
if [ -f "$ICON_SRC" ] && command -v sips >/dev/null 2>&1; then
  if sips -s format icns "$ICON_SRC" --out "$APP_BUNDLE/Contents/Resources/odysseus.icns" >/dev/null 2>&1; then
    echo "    icon: odysseus.icns"
  else
    echo "    icon: (skipped — sips conversion failed)"
  fi
else
  echo "    icon: (skipped — $ICON_SRC not found)"
fi

# Info.plist
BUNDLE_ID="${ODYSSEUS_BUNDLE_ID:-dev.odysseus.app}"
APP_VERSION="${ODYSSEUS_APP_VERSION:-0.1.0}"
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" -e "s/__APP_VERSION__/$APP_VERSION/g" \
  "$MACOS_DIR/Resources/Info.plist.template" > "$APP_BUNDLE/Contents/Info.plist"

# ── 4. Code sign ────────────────────────────────────────────────────────
echo "--> Code signing"
ENTITLEMENTS="$MACOS_DIR/Resources/Odysseus.entitlements"

sign() {
  local args=(--force --sign "$CODESIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
  if [ "$CODESIGN_IDENTITY" != "-" ]; then
    # --timestamp requires a real (non-ad-hoc) signing identity.
    args+=(--options runtime --timestamp)
  fi
  codesign "${args[@]}" "$1"
}

# Sign nested binaries/dylibs bottom-up before the outer bundle — more
# reliable for Gatekeeper/notarization than a single `codesign --deep` pass.
while IFS= read -r -d '' lib; do
  sign "$lib"
done < <(find "$APP_BUNDLE/Contents/Resources/backend" \( -name "*.so" -o -name "*.dylib" \) -print0)
sign "$APP_BUNDLE/Contents/Resources/backend/$APP_NAME"
sign "$APP_BUNDLE"

# ── 5. Notarize (only when credentials are configured) ──────────────────
if [ -n "${NOTARIZE_PROFILE:-}" ] && [ "$CODESIGN_IDENTITY" != "-" ]; then
  echo "--> Notarizing (profile: $NOTARIZE_PROFILE)"
  ZIP_FOR_NOTARY="$DIST/$APP_NAME-notarize.zip"
  ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_FOR_NOTARY"
  xcrun notarytool submit "$ZIP_FOR_NOTARY" --keychain-profile "$NOTARIZE_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  rm -f "$ZIP_FOR_NOTARY"
else
  echo "--> Skipping notarization (set CODESIGN_IDENTITY + NOTARIZE_PROFILE to enable)"
fi

# ── 6. Package .dmg ──────────────────────────────────────────────────────
echo "--> Packaging $DIST/$APP_NAME.dmg"
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP_BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME.dmg" >/dev/null
rm -rf "$STAGE"

echo ""
echo "Done:"
echo "  $APP_BUNDLE"
echo "  $DIST/$APP_NAME.dmg"
echo ""
echo "Run it:     open '$APP_BUNDLE'"
echo "Data dir:   ~/Library/Application Support/Odysseus"
echo "Backend log: ~/Library/Application Support/Odysseus/logs/backend.log"
