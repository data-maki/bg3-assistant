#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
mac_dir="$repo_dir/mac"
artifacts_dir="$repo_dir/artifacts/macos"
cd "$mac_dir"

fail() {
  echo "TestFlight build: $*" >&2
  exit 1
}

for secret_name in RELEASE_OPENROUTER_API_KEY OPENROUTER_API_KEY EXA_API_KEY; do
  [[ -z "${!secret_name:-}" ]] || fail "unset $secret_name; user provider credentials belong only in macOS Keychain."
done

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
[[ "$DEVELOPER_DIR" == *"Xcode.app/Contents/Developer" ]] || fail "select a full Xcode installation with xcode-select."
command -v xcodebuild >/dev/null || fail "xcodebuild is unavailable."

TEAM_ID="${DEVELOPMENT_TEAM:-X95828B7PG}"
BUNDLE_ID="${BUNDLE_ID:-com.datamaki.BG3HonorAssistant}"
MARKETING_VERSION="${MARKETING_VERSION:-1.1}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
UPLOAD_TO_APP_STORE="${UPLOAD_TO_APP_STORE:-1}"
APP_NAME="BG3HonorAssistant.app"
DISPLAY_NAME="BG3 Overlay"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$artifacts_dir/build/xcode}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$artifacts_dir/testflight/$DISPLAY_NAME.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$artifacts_dir/testflight/export}"
FINAL_PACKAGE="$artifacts_dir/testflight/packages/BG3-Overlay-$MARKETING_VERSION-$BUILD_NUMBER-TestFlight.pkg"

TEMP_DIR="$(mktemp -d)"
trap '/bin/rm -rf "$TEMP_DIR"' EXIT
ENTITLEMENTS="$TEMP_DIR/archive.entitlements"
RUNTIME_ENTITLEMENTS="$mac_dir/BG3Assistant/Resources/BG3HonorRuntime-AppStore.entitlements"
EXPORT_OPTIONS="$TEMP_DIR/export-options.plist"
UPLOAD_OPTIONS="$TEMP_DIR/upload-options.plist"

"$script_dir/build-app.sh" >/dev/null
RUNTIME_SOURCE="$artifacts_dir/app/BG3 Overlay.app/Contents/Resources/ollama"
[[ -x "$RUNTIME_SOURCE/ollama" ]] || fail "the verified Ollama runtime is missing."
[[ -f "$RUNTIME_ENTITLEMENTS" ]] || fail "the App Store runtime entitlements are missing."

/bin/rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH" "$(dirname "$FINAL_PACKAGE")" "$DERIVED_DATA_PATH"

xcodebuild archive \
  -project "BG3HonorAssistant.xcodeproj" \
  -scheme "BG3HonorAssistant" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  ENABLE_APP_SANDBOX=YES \
  ENABLE_OUTGOING_NETWORK_CONNECTIONS=YES \
  ENABLE_INCOMING_NETWORK_CONNECTIONS=YES \
  ENABLE_RESOURCE_ACCESS_AUDIO_INPUT=YES

ARCHIVED_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
[[ -x "$ARCHIVED_APP/Contents/MacOS/BG3HonorAssistant" ]] || fail "Xcode did not create the expected archive."
[[ -f "$ARCHIVED_APP/Contents/Resources/ItemIcons/safeguard-shield.webp" ]] || fail "the equipment item icons are missing from the archive."
[[ -f "$ARCHIVED_APP/Contents/Resources/BuildOptionIcons/magic-missile.webp" ]] || fail "the build option icons are missing from the archive."
[[ -f "$ARCHIVED_APP/Contents/Resources/CompanionPortraits/shadowheart.png" ]] || fail "the companion portraits are missing from the archive."
[[ -f "$ARCHIVED_APP/Contents/Resources/THIRD_PARTY_NOTICES.md" ]] || fail "the fan-content and runtime notices are missing from the archive."
[[ -f "$ARCHIVED_APP/Contents/Resources/PrivacyInfo.xcprivacy" ]] || fail "the privacy manifest is missing from the archive."
/usr/bin/ditto "$RUNTIME_SOURCE" "$ARCHIVED_APP/Contents/Resources/ollama"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$ARCHIVED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$ARCHIVED_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :ApplicationProperties:CFBundleShortVersionString $MARKETING_VERSION" "$ARCHIVE_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Set :ApplicationProperties:CFBundleVersion $BUILD_NUMBER" "$ARCHIVE_PATH/Info.plist"

/usr/bin/codesign -d --entitlements :- "$ARCHIVED_APP" > "$ENTITLEMENTS"
DIST_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk '/Apple Distribution/ { print $2; exit }')"
DEV_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk '/Apple Development/ { print $2; exit }')"
[[ -n "$DIST_IDENTITY" ]] || fail "an Apple Distribution identity is required."
[[ -n "$DEV_IDENTITY" ]] || fail "an Apple Development identity is required for the archive."

while IFS= read -r -d '' file; do
  file_description="$(/usr/bin/file -b "$file")"
  if [[ "$file_description" == *"MetalLib executable"* ]]; then
    /usr/bin/codesign --force --options runtime --sign "$DIST_IDENTITY" "$file"
    signature_info="$(/usr/bin/codesign -d --verbose=4 "$file" 2>&1)"
    [[ "$signature_info" == *"TeamIdentifier=$TEAM_ID"* ]] || fail "Metal library was not signed for team $TEAM_ID: $file"
  elif [[ "$file_description" == *"Mach-O"* ]]; then
    if [[ "$file_description" == *"executable"* ]]; then
      /usr/bin/codesign --force --options runtime --entitlements "$RUNTIME_ENTITLEMENTS" --sign "$DIST_IDENTITY" "$file"
    else
      /usr/bin/codesign --force --options runtime --sign "$DIST_IDENTITY" "$file"
    fi
  fi
done < <(find "$ARCHIVED_APP/Contents/Resources/ollama" -type f -print0)

/usr/bin/codesign \
  --force \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEV_IDENTITY" \
  "$ARCHIVED_APP"
/usr/bin/codesign --verify --deep --strict "$ARCHIVED_APP"

write_export_options() {
  local destination="$1"
  local output="$2"
  cat > "$output" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
  <key>testFlightInternalTestingOnly</key><false/>
</dict>
</plist>
PLIST
}

write_export_options export "$EXPORT_OPTIONS"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

EXPORTED_PACKAGE="$EXPORT_PATH/$DISPLAY_NAME.pkg"
[[ -f "$EXPORTED_PACKAGE" ]] || fail "Xcode did not export the expected installer package."
/usr/sbin/pkgutil --check-signature "$EXPORTED_PACKAGE"
/bin/rm -f "$FINAL_PACKAGE"
/bin/cp "$EXPORTED_PACKAGE" "$FINAL_PACKAGE"

if [[ "$UPLOAD_TO_APP_STORE" == "1" ]]; then
  write_export_options upload "$UPLOAD_OPTIONS"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$TEMP_DIR/upload" \
    -exportOptionsPlist "$UPLOAD_OPTIONS" \
    -allowProvisioningUpdates
fi

echo "$FINAL_PACKAGE"
