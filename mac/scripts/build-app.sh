#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
swift build

APP_DIR="CivCoach.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

/bin/rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp ".build/arm64-apple-macosx/debug/CivCoach" "$MACOS/CivCoach"
cp "CivCoach/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"
chmod +x "$MACOS/CivCoach"
SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')"
if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier com.local.CivCoach "$APP_DIR"
else
  /usr/bin/codesign --force --sign - --identifier com.local.CivCoach "$APP_DIR"
fi

echo "$PWD/$APP_DIR"
