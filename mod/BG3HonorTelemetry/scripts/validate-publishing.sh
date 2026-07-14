#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/source"
PAK="$ROOT/dist/BG3HonorTelemetry.pak"
THUMBNAIL="$ROOT/publishing/thumbnail.png"

xmllint --noout "$SOURCE/Mods/BG3HonorTelemetry/meta.lsx"
jq empty "$SOURCE/Mods/BG3HonorTelemetry/ScriptExtender/Config.json"

if command -v luac >/dev/null 2>&1; then
    luac -p "$SOURCE/Mods/BG3HonorTelemetry/ScriptExtender/Lua/BootstrapServer.lua"
fi

if find "$SOURCE" -type f \( -iname '*.exe' -o -iname '*.dll' \) | grep -q .; then
    echo "Unsupported executable file found in source" >&2
    exit 1
fi

LUA="$SOURCE/Mods/BG3HonorTelemetry/ScriptExtender/Lua/BootstrapServer.lua"
if rg -n 'Ext\.Osiris\.' "$LUA" | rg -v 'RegisterListener' >/dev/null; then
    echo "Unexpected Osiris mutation/call API found in telemetry source" >&2
    exit 1
fi

test -f "$THUMBNAIL"
WIDTH="$(sips -g pixelWidth "$THUMBNAIL" | awk '/pixelWidth/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "$THUMBNAIL" | awk '/pixelHeight/ {print $2}')"
BYTES="$(stat -f%z "$THUMBNAIL")"
test "$WIDTH" -ge 512
test "$HEIGHT" -ge 288
test "$BYTES" -le 8388608

test -f "$PAK"

OLIVER="${OLIVER:-$(command -v oliver || true)}"
if [[ -n "$OLIVER" && -x "$OLIVER" ]]; then
    TMPDIR_PAK="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR_PAK"' EXIT
    "$OLIVER" parse "$PAK" >/dev/null
    "$OLIVER" unpack -d "$TMPDIR_PAK" "$PAK"
    diff -qr "$SOURCE" "$TMPDIR_PAK"
fi

echo "Package: $(shasum -a 256 "$PAK" | awk '{print $1}')"
echo "Thumbnail: ${WIDTH}x${HEIGHT}, ${BYTES} bytes"
if [[ -n "$OLIVER" && -x "$OLIVER" ]]; then
    echo "Archive: metadata parsed and unpacked contents match source"
else
    echo "Archive: round-trip skipped (set OLIVER=/absolute/path/to/oliver)"
fi
echo "Local artifact checks passed. Official Mod.io eligibility remains blocked; see PUBLISHING_AUDIT.md."
