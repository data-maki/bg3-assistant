#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/../.." && pwd)"
mac_dir="$repo_dir/mac"
scratch_dir="$repo_dir/artifacts/macos/build/validation"

mkdir -p "$scratch_dir"

swift build --package-path "$mac_dir" --scratch-path "$scratch_dir"
swift test --package-path "$mac_dir" --scratch-path "$scratch_dir"
xcodebuild \
  -project "$mac_dir/BG3HonorAssistant.xcodeproj" \
  -scheme BG3HonorAssistant \
  -configuration Debug \
  -derivedDataPath "$repo_dir/artifacts/macos/build/xcode-validation" \
  CODE_SIGNING_ALLOWED=NO \
  build
git -C "$repo_dir" diff --check

unexpected_output="$(find "$mac_dir" -maxdepth 1 \( \
  -name '.build' -o \
  -name '.swiftpm' -o \
  -name '*.app' -o \
  -name '*.pkg' -o \
  -name '*.zip' \
\) -print)"

if [[ -n "$unexpected_output" ]]; then
  printf 'Generated output leaked into mac/:\n%s\n' "$unexpected_output" >&2
  exit 1
fi

printf 'macOS app validation passed. Generated output: %s\n' "$scratch_dir"
