#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
mac_dir="$repo_dir/mac"
scratch_dir="$repo_dir/artifacts/macos/build/readme-capture"
output_dir="$repo_dir/docs/images"

for dependency in ffmpeg jq sqlite3; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$dependency" >&2
    exit 1
  fi
done

if pgrep -f '[B]G3HonorAssistant' >/dev/null; then
  printf 'Quit BG3 Overlay before capturing README media.\n' >&2
  exit 1
fi

if [[ ! -d "$output_dir" ]]; then
  printf 'README image directory does not exist: %s\n' "$output_dir" >&2
  exit 1
fi

workspace="$(mktemp -d "${TMPDIR%/}/bg3-readme.XXXXXX")"
trap 'rm -rf "$workspace"' EXIT
state_dir="$workspace/state"
mkdir "$state_dir"
database="$state_dir/state.sqlite3"

progress="$(jq -c 'reduce (.[] | select(.order < 38) | .id) as $id ({}; .[$id] = "completed")' "$repo_dir/data/act1_walkthrough.json")"
snapshot="$workspace/run.json"
jq -cn --argjson walkthroughProgress "$progress" '{
  id: "readme-demo",
  name: "BG3 Run",
  guideVersion: "2026-07-18-all-act-review-v2",
  party: [
    {id: "tav", name: "Tav", level: 5, buildId: "SB-A1", preparedTags: [], className: "Bard", appliedAbilitySetupId: "creation"},
    {id: "companion-1", name: "Shadowheart", level: 5, buildId: "CL-102", preparedTags: [], className: "Cleric", appliedAbilitySetupId: "creation"},
    {id: "companion-2", name: "Lae\u0027zel", level: 5, buildId: "MO-OH", preparedTags: [], className: "Monk", appliedAbilitySetupId: "creation"},
    {id: "companion-3", name: "Astarion", level: 5, buildId: "SB-1011", preparedTags: [], className: "Bard", appliedAbilitySetupId: "creation"}
  ],
  progress: {},
  walkthroughProgress: $walkthroughProgress,
  walkthroughOutcomes: {},
  focusedWalkthroughStepId: "walk-spectator",
  selectedAct: 1,
  mapRegion: "Wilderness"
}' > "$snapshot"

sqlite3 "$database" "CREATE TABLE runs(run_id TEXT PRIMARY KEY, snapshot_json TEXT NOT NULL, updated_at REAL NOT NULL, is_active INTEGER NOT NULL DEFAULT 0); CREATE UNIQUE INDEX one_active_run ON runs(is_active) WHERE is_active = 1; CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at REAL NOT NULL); INSERT INTO runs VALUES('readme-demo', CAST(readfile('$snapshot') AS TEXT), strftime('%s','now'), 1); INSERT INTO settings VALUES('assistant', '{\"overlayDensity\":\"focus\",\"onboardingSeenVersion\":2,\"seenHints\":[\"plannerMap\"]}', strftime('%s','now'));"

mkdir -p "$scratch_dir"
swift build --package-path "$mac_dir" --scratch-path "$scratch_dir" -Xswiftc -DREADME_CAPTURE
bin_path="$(swift build --package-path "$mac_dir" --scratch-path "$scratch_dir" -Xswiftc -DREADME_CAPTURE --show-bin-path)"
binary="$bin_path/BG3HonorAssistant"

for tab in now route party loadout act; do
  BG3_ASSISTANT_STATE_DIR="$state_dir" \
  BG3_ASSISTANT_DEBUG_TAB="$tab" \
  BG3_ASSISTANT_DEBUG_CAPTURE_PATH="$output_dir/overlay-$tab.png" \
    "$binary"
  test -s "$output_dir/overlay-$tab.png"
done

ffmpeg -hide_banner -loglevel error -y \
  -loop 1 -t 2 -i "$output_dir/overlay-now.png" \
  -loop 1 -t 2 -i "$output_dir/overlay-route.png" \
  -loop 1 -t 2 -i "$output_dir/overlay-party.png" \
  -loop 1 -t 2 -i "$output_dir/overlay-loadout.png" \
  -filter_complex "[0:v]scale=840:-1,pad=840:900:0:(oh-ih)/2:color=0x0b0908,fps=10,format=rgb24[v0];[1:v]scale=840:-1,crop=840:900:0:0,fps=10,format=rgb24[v1];[2:v]scale=840:-1,crop=840:900:0:0,fps=10,format=rgb24[v2];[3:v]scale=840:-1,crop=840:900:0:0,fps=10,format=rgb24[v3];[v0][v1][v2][v3]concat=n=4:v=1:a=0,split[p0][p1];[p0]palettegen=stats_mode=diff[p];[p1][p]paletteuse=dither=bayer:bayer_scale=4" \
  -loop 0 "$output_dir/product-tour.gif"

printf 'Updated README media in %s\n' "$output_dir"
