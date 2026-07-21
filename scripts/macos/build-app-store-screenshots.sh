#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
source_dir="$repo_dir/docs/images"
output_dir="$repo_dir/docs/app-store/screenshots"
renderer_source="$script_dir/render-app-store-screenshot.swift"

command -v xcrun >/dev/null 2>&1 || { printf 'Missing required command: xcrun\n' >&2; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { printf 'Missing required command: ffmpeg\n' >&2; exit 1; }
[[ -f "$renderer_source" ]] || { printf 'Screenshot renderer is missing: %s\n' "$renderer_source" >&2; exit 1; }
[[ -d "$output_dir" ]] || { printf 'Screenshot output directory does not exist: %s\n' "$output_dir" >&2; exit 1; }

workspace="$(mktemp -d "${TMPDIR%/}/bg3-app-store.XXXXXX")"
trap '/bin/rm -rf "$workspace"' EXIT
renderer="$workspace/render-app-store-screenshot"
xcrun swiftc "$renderer_source" -o "$renderer" -framework AppKit

make_screenshot() {
  local number="$1"
  local source_name="$2"
  local output_name="$3"
  local title="$4"
  local detail_one="$5"
  local detail_two="$6"
  local panel_width="$7"
  local source="$source_dir/$source_name"
  local output="$output_dir/$output_name"
  local rendered="$workspace/$output_name"

  [[ -f "$source" ]] || { printf 'Missing source capture: %s\n' "$source" >&2; exit 1; }

  "$renderer" \
    "$source" \
    "$rendered" \
    "$number" \
    "$title" \
    "$detail_one" \
    "$detail_two" \
    "$panel_width"

  ffmpeg -hide_banner -loglevel error -y \
    -i "$rendered" \
    -vf format=rgb24 \
    "$output"
}

make_screenshot "01" "overlay-now.png" "01-next-move.png" \
  "KNOW THE NEXT MOVE" \
  "Keep the current objective and warnings" \
  "visible while you play" \
  "620"

make_screenshot "02" "overlay-route.png" "02-plan-the-run.png" \
  "PLAN THE RUN" \
  "Follow dependencies decisions and missed steps" \
  "in one Honor Mode route" \
  "570"

make_screenshot "03" "overlay-party.png" "03-build-the-party.png" \
  "BUILD THE WHOLE PARTY" \
  "Keep levels classes abilities and targets" \
  "aligned across your whole active party" \
  "570"

make_screenshot "04" "overlay-loadout.png" "04-track-every-slot.png" \
  "TRACK EVERY SLOT" \
  "Compare equipped gear with act targets" \
  "before the next difficult fight" \
  "530"

make_screenshot "05" "overlay-act.png" "05-close-the-act.png" \
  "CLOSE EACH ACT CLEANLY" \
  "Review objectives and missed gear" \
  "before an irreversible act transition" \
  "570"

printf 'Created App Store screenshots in %s\n' "$output_dir"
