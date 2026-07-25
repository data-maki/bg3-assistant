#!/usr/bin/env bash
set -euo pipefail

app_name="BG3 Overlay.app"
executable_name="BG3HonorAssistant"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_dir="${INSTALL_DIR:-$HOME/Applications}"
target="$install_dir/$app_name"
stage_root=""
backup_root=""
target_displaced=0
new_installed=0
install_succeeded=0

fail() {
  printf 'Install failed: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [[ "$install_succeeded" -ne 1 ]]; then
    if [[ "$new_installed" -eq 1 && -e "$target" ]]; then
      /bin/rm -rf "$target"
    fi
    if [[ "$target_displaced" -eq 1 && -n "$backup_root" && -e "$backup_root/$app_name" ]]; then
      /bin/mv "$backup_root/$app_name" "$target"
    fi
  fi
  if [[ -n "$stage_root" && -e "$stage_root" ]]; then /bin/rm -rf "$stage_root"; fi
  if [[ -n "$backup_root" && -e "$backup_root" ]]; then /bin/rm -rf "$backup_root"; fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ "$(uname -s)" == "Darwin" ]] || fail "this installer runs only on macOS."

if [[ "$(uname -m)" == "x86_64" && "$(sysctl -in sysctl.proc_translated 2>/dev/null || true)" == "1" ]]; then
  exec /usr/bin/arch -arm64 /bin/bash "$0" "$@"
fi
[[ "$(uname -m)" == "arm64" ]] || fail "Apple silicon is required."

macos_version="$(sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
[[ "$macos_major" =~ ^[0-9]+$ && "$macos_major" -ge 14 ]] || fail "macOS 14 or later is required."

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1 || true
  fail "Apple Command Line Tools are required. Finish the installer that just opened, then run this script again."
fi

swift_version="$(swift --version 2>/dev/null || true)"
if [[ ! "$swift_version" =~ Swift[[:space:]]version[[:space:]]([0-9]+) ]] || [[ "${BASH_REMATCH[1]}" -lt 6 ]]; then
  fail "Swift 6 is required. Update Xcode or Apple Command Line Tools, then try again."
fi

printf 'Building the self-contained app bundle...\n'
/bin/bash "$script_dir/scripts/macos/build-app.sh"
built_app="$script_dir/artifacts/macos/app/$app_name"

verify_bundle() {
  local app="$1"
  [[ -x "$app/Contents/MacOS/$executable_name" ]] || return 1
  [[ -x "$app/Contents/Resources/ollama/ollama" ]] || return 1
  [[ -f "$app/Contents/Resources/Data/guide-bundle.json" ]] || return 1
  [[ ! -e "$app/Contents/Resources/backend" ]] || return 1
  /usr/bin/codesign --verify --deep --strict "$app" || return 1
  [[ " $(/usr/bin/lipo -archs "$app/Contents/MacOS/$executable_name") " == *" arm64 "* ]] || return 1
  [[ " $(/usr/bin/lipo -archs "$app/Contents/Resources/ollama/ollama") " == *" arm64 "* ]] || return 1
}

verify_bundle "$built_app" || fail "the built app did not pass bundle, architecture, and signature checks."

if [[ -L "$target" ]]; then fail "refusing to replace the symlink at $target"; fi
if [[ -e "$target" && ( ! -d "$target" || ! -x "$target/Contents/MacOS/$executable_name" ) ]]; then
  fail "refusing to replace an unexpected item at $target"
fi

if pgrep -x "$executable_name" >/dev/null 2>&1; then
  /usr/bin/osascript -e 'quit app "BG3 Overlay"' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! pgrep -x "$executable_name" >/dev/null 2>&1; then break; fi
    /bin/sleep 1
  done
  pgrep -x "$executable_name" >/dev/null 2>&1 && fail "quit the running app and run the installer again."
fi

/bin/mkdir -p "$install_dir"
[[ -w "$install_dir" ]] || fail "$install_dir is not writable. Use the default ~/Applications or set INSTALL_DIR to a writable folder."

stage_root="$(mktemp -d "$install_dir/.bg3-install.XXXXXX")"
staged_app="$stage_root/$app_name"
/usr/bin/ditto "$built_app" "$staged_app"
/usr/bin/xattr -dr com.apple.quarantine "$staged_app" 2>/dev/null || true
verify_bundle "$staged_app" || fail "the staged app failed verification."

if [[ -e "$target" ]]; then
  backup_root="$(mktemp -d "$install_dir/.bg3-backup.XXXXXX")"
  /bin/mv "$target" "$backup_root/$app_name"
  target_displaced=1
fi

new_installed=1
/bin/mv "$staged_app" "$target"
verify_bundle "$target" || fail "the installed app failed verification; the previous copy will be restored."

install_succeeded=1
if [[ "$target_displaced" -eq 1 ]]; then
  /bin/rm -rf "$backup_root"
  backup_root=""
  target_displaced=0
fi
/bin/rm -rf "$stage_root"
stage_root=""

printf 'Installed %s\n' "$target"
printf 'Choose Local Qwen or OpenRouter during setup. Local Qwen downloads its model separately.\n'

if [[ "${OPEN_AFTER_INSTALL:-1}" == "1" ]]; then
  /usr/bin/open "$target"
fi
