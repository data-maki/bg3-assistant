#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' 'BG3 Honor Mode Assistant.app/Contents/Info.plist')"
ARCHIVE="BG3-Honor-Mode-Assistant-${VERSION}-macOS-arm64.zip"
APP="BG3 Honor Mode Assistant.app"
REQUIRE_RELEASE_SIGNING="${REQUIRE_RELEASE_SIGNING:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
SIGNING_INFO="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1)"
if [[ "$REQUIRE_RELEASE_SIGNING" == "1" ]]; then
  if ! grep -q '^Authority=Developer ID Application:' <<<"$SIGNING_INFO"; then
    echo "Public release requires a Developer ID Application certificate." >&2
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "Public release requires NOTARY_PROFILE for notarytool." >&2
    exit 1
  fi
fi

rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ARCHIVE"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
fi

if [[ "$REQUIRE_RELEASE_SIGNING" == "1" ]]; then
  spctl --assess --type execute --verbose=2 "$APP"
else
  spctl --assess --type execute --verbose=2 "$APP" || true
fi
shasum -a 256 "$ARCHIVE"
echo "$PWD/$ARCHIVE"
