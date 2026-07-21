#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
artifacts_dir="$repo_dir/artifacts/macos"
app="$artifacts_dir/app/BG3 Honor Mode Assistant.app"
release_dir="$artifacts_dir/releases"

"$script_dir/build-app.sh"
mkdir -p "$release_dir"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
ARCHIVE="$release_dir/BG3-Honor-Mode-Assistant-${VERSION}-macOS-arm64.zip"
REQUIRE_RELEASE_SIGNING="${REQUIRE_RELEASE_SIGNING:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
SIGNING_INFO="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)"
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
ditto -c -k --sequesterRsrc --keepParent "$app" "$ARCHIVE"
if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  rm -f "$ARCHIVE"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$ARCHIVE"
fi

if [[ "$REQUIRE_RELEASE_SIGNING" == "1" ]]; then
  spctl --assess --type execute --verbose=2 "$app"
else
  spctl --assess --type execute --verbose=2 "$app" || true
fi
shasum -a 256 "$ARCHIVE"
echo "$ARCHIVE"
