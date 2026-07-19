#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT_DIR="$(cd .. && pwd)"
BUNDLE_ID="${BUNDLE_ID:-com.datamaki.BG3HonorAssistant}"
BUILD_BACKEND="${BUILD_BACKEND:-1}"
SWIFT_SCRATCH_PATH="${SWIFT_SCRATCH_PATH:-.build}"

if [[ -n "${RELEASE_OPENROUTER_API_KEY:-}" ]]; then
  echo "RELEASE_OPENROUTER_API_KEY is no longer supported; keep provider credentials on the hosted backend." >&2
  exit 1
fi

read_dotenv_value() {
  local key="$1"
  local file="$2"
  local line value
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=(.*)$ ]]; then
      value="${BASH_REMATCH[1]}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
        value="${value:1:${#value}-2}"
      fi
      printf '%s' "$value"
      return 0
    fi
  done < "$file"
}

BG3_BACKEND_URL="${BG3_BACKEND_URL:-$(read_dotenv_value BG3_BACKEND_URL "$ROOT_DIR/.env")}"
BG3_BACKEND_URL="${BG3_BACKEND_URL:-http://127.0.0.1:8787}"
BG3_BACKEND_URL="${BG3_BACKEND_URL%/}"
if [[ "$BG3_BACKEND_URL" == "http://127.0.0.1:8787" ]]; then
  :
elif [[ "$BG3_BACKEND_URL" =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?$ ]]; then
  :
else
  echo "BG3_BACKEND_URL must be http://127.0.0.1:8787 or an HTTPS origin without credentials, path, query, or fragment." >&2
  exit 1
fi

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
/usr/libexec/PlistBuddy -c "Set :BG3BackendURL $BG3_BACKEND_URL" "$CONTENTS/Info.plist"
ICON_SOURCE="BG3Assistant/Resources/AppIcon.icns"
test -f "$ICON_SOURCE"
cp "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"
PET_SOURCE="BG3Assistant/Resources/twilight-cleric.webp"
test -f "$PET_SOURCE"
cp "$PET_SOURCE" "$RESOURCES/twilight-cleric.webp"
BACKEND_DIST="$ROOT_DIR/backend/dist/bg3-honor-backend"
test -x "$BACKEND_DIST/bg3-honor-backend"
if /usr/bin/find "$BACKEND_DIST" -name '.env' -print -quit | /usr/bin/grep -q .; then
  echo "Refusing to package a backend distribution containing a .env file." >&2
  exit 1
fi
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
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

echo "$PWD/$APP_DIR"
