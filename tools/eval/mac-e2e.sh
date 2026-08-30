#!/usr/bin/env bash
# Automated macOS e2e (synthetic OCR→Engine→Present; SCKit optional).
# Usage: bash tools/eval/mac-e2e.sh [--e2e-llama]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/tools/eval/out"
mkdir -p "$OUT"
cd "$ROOT/mac"
swift build -c release --product LensTrans
BIN="$ROOT/mac/.build/release/LensTrans"
EXTRA=("$@")
if [[ ${#EXTRA[@]} -eq 0 ]]; then
  # Default: include local llama when GGUF is present.
  NAME=qwen2.5-0.5b-instruct-q4_k_m.gguf
  if [[ -f "$HOME/Library/Application Support/LensTrans/models/$NAME" ]]; then
    EXTRA=(--e2e-llama)
  fi
fi
set +e
"$BIN" --e2e --e2e-sec 8 --no-onboard --e2e-out "$OUT/mac-e2e.md" "${EXTRA[@]}"
CODE=$?
set -e
echo "mac-e2e exit=$CODE report=$OUT/mac-e2e.md"
exit "$CODE"
