#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(cd .. && pwd)"
BUNDLE_ID="${BUNDLE_ID:-com.datamaki.BG3HonorAssistant}"
BUILD_BACKEND="${BUILD_BACKEND:-1}"
SWIFT_SCRATCH_PATH="${SWIFT_SCRATCH_PATH:-.build}"

if [[ "$BUILD_BACKEND" == "1" ]]; then
  "$ROOT_DIR/backend/scripts/build-standalone.sh"
fi

swift build -c release --scratch-path "$SWIFT_SCRATCH_PATH"

APP_DIR="BG3 Honor Mode Assistant.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

/bin/rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$SWIFT_SCRATCH_PATH/arm64-apple-macosx/release/BG3HonorAssistant" "$MACOS/BG3HonorAssistant"
cp "BG3Assistant/Resources/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
ICON_SOURCE="BG3Assistant/Resources/AppIcon.icns"
test -f "$ICON_SOURCE"
cp "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"
PET_SOURCE="BG3Assistant/Resources/twilight-cleric.webp"
test -f "$PET_SOURCE"
cp "$PET_SOURCE" "$RESOURCES/twilight-cleric.webp"
BACKEND_DIST="$ROOT_DIR/backend/dist/bg3-honor-backend"
test -x "$BACKEND_DIST/bg3-honor-backend"
cp -R "$BACKEND_DIST" "$RESOURCES/backend"
printf 'APPL????' > "$CONTENTS/PkgInfo"
chmod +x "$MACOS/BG3HonorAssistant"
SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi
ENTITLEMENTS="BG3Assistant/Resources/BG3HonorAssistant.entitlements"
if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
else
  /usr/bin/codesign --force --deep --entitlements "$ENTITLEMENTS" --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
fi

echo "$PWD/$APP_DIR"
