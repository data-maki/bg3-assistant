#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
mac_dir="$repo_dir/mac"
source_resources="$repo_dir/Resources"
artifacts_dir="$repo_dir/artifacts/macos"
BUNDLE_ID="${BUNDLE_ID:-com.datamaki.BG3HonorAssistant}"
SWIFT_SCRATCH_PATH="$artifacts_dir/build/swift"
APP_DIR="$artifacts_dir/app/BG3 Overlay.app"
OLLAMA_VERSION="v0.30.10"
OLLAMA_SHA256="ad8a4d2918ed09480b8160419570602b4f49e48c9e3792efb601c0f54619e48e"

if [[ -n "${RELEASE_OPENROUTER_API_KEY:-}" ]]; then
  echo "RELEASE_OPENROUTER_API_KEY is not supported; users supply credentials through Keychain." >&2
  exit 1
fi

mkdir -p "$SWIFT_SCRATCH_PATH" "$(dirname "$APP_DIR")"
cd "$mac_dir"

swift build -c release --scratch-path "$SWIFT_SCRATCH_PATH"
SWIFT_BIN_DIR="$(swift build -c release --scratch-path "$SWIFT_SCRATCH_PATH" --show-bin-path)"

CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

/bin/rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$SWIFT_BIN_DIR/BG3HonorAssistant" "$MACOS/BG3HonorAssistant"
cp "$source_resources/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS/Info.plist"
ICON_SOURCE="$source_resources/AppIcon.icns"
test -f "$ICON_SOURCE"
cp "$ICON_SOURCE" "$RESOURCES/AppIcon.icns"
PET_SOURCE="$source_resources/twilight-cleric.webp"
test -f "$PET_SOURCE"
cp "$PET_SOURCE" "$RESOURCES/twilight-cleric.webp"
GUIDE_SOURCE="$source_resources/Data/guide-bundle.json"
test -f "$GUIDE_SOURCE"
mkdir -p "$RESOURCES/Data"
cp "$GUIDE_SOURCE" "$RESOURCES/Data/guide-bundle.json"
ITEM_ICONS_SOURCE="$source_resources/ItemIcons"
test -d "$ITEM_ICONS_SOURCE"
cp -R "$ITEM_ICONS_SOURCE" "$RESOURCES/ItemIcons"
BUILD_OPTION_ICONS_SOURCE="$source_resources/BuildOptionIcons"
test -d "$BUILD_OPTION_ICONS_SOURCE"
cp -R "$BUILD_OPTION_ICONS_SOURCE" "$RESOURCES/BuildOptionIcons"
COMPANION_PORTRAITS_SOURCE="$source_resources/CompanionPortraits"
test -d "$COMPANION_PORTRAITS_SOURCE"
cp -R "$COMPANION_PORTRAITS_SOURCE" "$RESOURCES/CompanionPortraits"
NOTICES_SOURCE="$source_resources/THIRD_PARTY_NOTICES.md"
test -f "$NOTICES_SOURCE"
cp "$NOTICES_SOURCE" "$RESOURCES/THIRD_PARTY_NOTICES.md"
PRIVACY_MANIFEST_SOURCE="$source_resources/PrivacyInfo.xcprivacy"
test -f "$PRIVACY_MANIFEST_SOURCE"
cp "$PRIVACY_MANIFEST_SOURCE" "$RESOURCES/PrivacyInfo.xcprivacy"

OLLAMA_ARCHIVE="$SWIFT_SCRATCH_PATH/ollama-darwin-$OLLAMA_VERSION.tgz"
OLLAMA_DIST="$SWIFT_SCRATCH_PATH/ollama-darwin-$OLLAMA_VERSION"
if [[ ! -f "$OLLAMA_ARCHIVE" ]]; then
  curl --fail --location --silent --show-error \
    "https://github.com/ollama/ollama/releases/download/$OLLAMA_VERSION/ollama-darwin.tgz" \
    --output "$OLLAMA_ARCHIVE"
fi
ACTUAL_OLLAMA_SHA="$(shasum -a 256 "$OLLAMA_ARCHIVE" | cut -d ' ' -f 1)"
if [[ "$ACTUAL_OLLAMA_SHA" != "$OLLAMA_SHA256" ]]; then
  echo "Ollama archive checksum mismatch." >&2
  exit 1
fi
/bin/rm -rf "$OLLAMA_DIST"
mkdir -p "$OLLAMA_DIST"
tar -xzf "$OLLAMA_ARCHIVE" -C "$OLLAMA_DIST"
test -x "$OLLAMA_DIST/ollama"
cp -R "$OLLAMA_DIST" "$RESOURCES/ollama"
printf 'APPL????' > "$CONTENTS/PkgInfo"
chmod +x "$MACOS/BG3HonorAssistant"
SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F '"' '/Apple Development/ { print $2; exit }')"
fi
ENTITLEMENTS="$source_resources/BG3HonorAssistant.entitlements"
if [[ -n "$SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
else
  /usr/bin/codesign --force --deep --entitlements "$ENTITLEMENTS" --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
fi
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
