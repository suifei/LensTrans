#!/usr/bin/env bash
# macOS host gate for LensTrans App + Logic.
# Usage: bash tools/eval/mac-smoke.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/tools/eval/out"
mkdir -p "$OUT"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
LOG="$OUT/mac-smoke-$STAMP.txt"
{
  echo "host=$(uname -a)"
  echo "swift=$(swift --version 2>&1 | head -1)"
  echo "pwd=$ROOT"
  echo "--- swift test ---"
  (cd "$ROOT/mac" && swift test)
  echo "--- swift build -c release ---"
  (cd "$ROOT/mac" && swift build -c release --product LensTrans)
  BIN="$ROOT/mac/.build/release/LensTrans"
  echo "binary=$BIN"
  test -x "$BIN"
  ls -la "$BIN"
  echo "--- llama-cli ---"
  if command -v llama-cli >/dev/null 2>&1; then
    echo "llama-cli=$(command -v llama-cli)"
    llama-cli --version 2>&1 | head -3 || true
  else
    echo "llama-cli=MISSING (local engine will report not found until installed)"
  fi
  echo "--- model ---"
  NAME=qwen2.5-0.5b-instruct-q4_k_m.gguf
  FOUND=""
  for p in \
    "$HOME/Library/Application Support/LensTrans/models/$NAME" \
    "$ROOT/models/$NAME" \
    "$HOME/works/LensTrans/models/$NAME"; do
    if [[ -f "$p" ]]; then FOUND="$p"; break; fi
  done
  if [[ -n "$FOUND" ]]; then
    echo "gguf=$FOUND"
    ls -la "$FOUND"
  else
    echo "gguf=MISSING (download via onboarding or models/README.md)"
  fi
  echo "--- mac-logic-verify ---"
  python3 "$ROOT/tools/eval/mac-logic-verify.py"
  echo "--- mac-ocr-smoke ---"
  swift "$ROOT/tools/eval/mac-ocr-smoke.swift"
  echo "RESULT=PASS"
} | tee "$LOG"
echo "wrote $LOG"
