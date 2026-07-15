#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail() {
  echo "TestFlight build: $*" >&2
  exit 1
}

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
[[ "$DEVELOPER_DIR" == *"Xcode.app/Contents/Developer" ]] || fail "install full Xcode 16 or later and select it with xcode-select."
command -v xcodebuild >/dev/null || fail "xcodebuild is unavailable."
XCODE_MAJOR="$(xcodebuild -version | awk 'NR == 1 { split($2, version, "."); print version[1] }')"
[[ "$XCODE_MAJOR" =~ ^[0-9]+$ && "$XCODE_MAJOR" -ge 16 ]] || fail "Xcode 16 or later is required by this Swift 6 package."

PROFILE="${APP_STORE_PROFILE:-}"
[[ -n "$PROFILE" && -f "$PROFILE" ]] || fail "set APP_STORE_PROFILE to the Mac App Store provisioning profile."

APP_IDENTITY="${APP_STORE_APPLICATION_IDENTITY:-}"
if [[ -z "$APP_IDENTITY" ]]; then
  APP_IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | awk -F '"' '/Apple Distribution/ { print $2; exit }')"
fi
[[ -n "$APP_IDENTITY" ]] || fail "install an Apple Distribution certificate or set APP_STORE_APPLICATION_IDENTITY."

INSTALLER_IDENTITY="${APP_STORE_INSTALLER_IDENTITY:-}"
[[ -n "$INSTALLER_IDENTITY" ]] || fail "set APP_STORE_INSTALLER_IDENTITY to a Mac Installer Distribution certificate name."

BUNDLE_ID="${BUNDLE_ID:-com.datamaki.BG3HonorAssistant}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
MARKETING_VERSION="${MARKETING_VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' BG3Assistant/Resources/Info.plist)}"
APP="BG3 Honor Mode Assistant.app"
PKG="BG3-Honor-Mode-Assistant-${MARKETING_VERSION}-${BUILD_NUMBER}-TestFlight.pkg"
HELPER_ENTITLEMENTS="BG3Assistant/Resources/BG3HonorBackend-AppStore.entitlements"

TEMP_DIR="$(mktemp -d)"
trap '/bin/rm -rf "$TEMP_DIR"' EXIT
PROFILE_PLIST="$TEMP_DIR/profile.plist"
MAIN_ENTITLEMENTS="$TEMP_DIR/app.entitlements"

security cms -D -i "$PROFILE" -o "$PROFILE_PLIST"
plutil -extract Entitlements xml1 -o "$MAIN_ENTITLEMENTS" "$PROFILE_PLIST"
PROFILE_APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$PROFILE_PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST" 2>/dev/null || true)"
[[ "$PROFILE_APP_ID" == *".$BUNDLE_ID" ]] || fail "the provisioning profile does not include $BUNDLE_ID."

set_entitlement() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Set :$key true" "$MAIN_ENTITLEMENTS" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :$key bool true" "$MAIN_ENTITLEMENTS"
}

set_entitlement com.apple.security.app-sandbox
set_entitlement com.apple.security.device.audio-input
set_entitlement com.apple.security.network.client
set_entitlement com.apple.security.network.server

BUNDLE_ID="$BUNDLE_ID" ./scripts/build-app.sh
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$APP/Contents/Info.plist"
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

BACKEND="$APP/Contents/Resources/backend"
while IFS= read -r -d '' file; do
  if /usr/bin/file -b "$file" | grep -q 'Mach-O'; then
    /usr/bin/codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" "$file"
  fi
done < <(find "$BACKEND" -type f -print0)

/usr/bin/codesign \
  --force --timestamp --options runtime \
  --entitlements "$HELPER_ENTITLEMENTS" \
  --sign "$APP_IDENTITY" \
  "$BACKEND/bg3-honor-backend"

/usr/bin/codesign \
  --force --timestamp --options runtime \
  --entitlements "$MAIN_ENTITLEMENTS" \
  --sign "$APP_IDENTITY" \
  "$APP"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/bin/rm -f "$PKG"
/usr/bin/productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
/usr/sbin/pkgutil --check-signature "$PKG"

echo "$PWD/$PKG"
