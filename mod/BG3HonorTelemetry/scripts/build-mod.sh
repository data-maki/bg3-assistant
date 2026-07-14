#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
SOURCE="$ROOT/source"
DIST="$ROOT/dist"
OUTPUT="$DIST/BG3HonorTelemetry.pak"
DIVINE_BIN="${DIVINE:-}"
OLIVER_BIN="${OLIVER:-}"

mkdir -p "$DIST"
if [[ -z "$OLIVER_BIN" ]]; then
  OLIVER_BIN="$(command -v oliver || true)"
fi
if [[ -n "$OLIVER_BIN" ]]; then
  "$OLIVER_BIN" pack "$SOURCE" --destination "$OUTPUT"
  print "Built $OUTPUT"
  exit 0
fi
if [[ -z "$DIVINE_BIN" ]]; then
  DIVINE_BIN="$(command -v divine || command -v Divine || true)"
fi
if [[ -z "$DIVINE_BIN" ]]; then
  print -u2 "BG3 .pak builder not found. Install 'oliver' or the official Toolkit/Divine toolchain, then set OLIVER= or DIVINE= when it is not on PATH."
  exit 2
fi

"$DIVINE_BIN" -g bg3 -a create-package -s "$SOURCE" -d "$OUTPUT" -c lz4
print "Built $OUTPUT"
