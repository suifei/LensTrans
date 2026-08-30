#!/usr/bin/env bash
# Automated macOS e2e (synthetic OCR→Engine→Present; SCKit optional).
# Usage:
#   bash tools/eval/mac-e2e.sh [--e2e-llama]
#   bash tools/eval/mac-e2e.sh --app   # use dist/macos/LensTrans.app if present
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/tools/eval/out"
mkdir -p "$OUT"
USE_APP=0
PASS=()
for a in "$@"; do
  if [[ "$a" == "--app" ]]; then USE_APP=1; else PASS+=("$a"); fi
done
APP_BIN="$ROOT/dist/macos/LensTrans.app/Contents/MacOS/LensTrans"
if [[ "$USE_APP" -eq 1 && -x "$APP_BIN" ]]; then
  BIN="$APP_BIN"
  echo "using bundled app binary: $BIN"
else
  cd "$ROOT/mac"
  swift build -c release --product LensTrans
  BIN="$ROOT/mac/.build/release/LensTrans"
fi
if [[ ${#PASS[@]} -gt 0 ]]; then
  EXTRA=("${PASS[@]}")
else
  EXTRA=()
fi
if [[ ${#EXTRA[@]} -eq 0 ]]; then
  # Default: include local llama when GGUF is present.
  NAME=qwen2.5-0.5b-instruct-q4_k_m.gguf
  if [[ -f "$HOME/Library/Application Support/LensTrans/models/$NAME" ]]; then
    EXTRA=(--e2e-llama)
  fi
fi
REPORT="$OUT/mac-e2e.md"
if [[ "$USE_APP" -eq 1 ]]; then REPORT="$OUT/mac-e2e-app.md"; fi
set +e
"$BIN" --e2e --e2e-sec 8 --no-onboard --e2e-out "$REPORT" "${EXTRA[@]}"
CODE=$?
set -e
echo "mac-e2e exit=$CODE report=$REPORT bin=$BIN"
exit "$CODE"
