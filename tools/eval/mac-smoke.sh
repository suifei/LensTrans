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
  echo "--- llama-cli / llama-completion ---"
  if command -v llama-completion >/dev/null 2>&1; then
    echo "llama-completion=$(command -v llama-completion)"
  elif command -v llama-cli >/dev/null 2>&1; then
    echo "llama-cli=$(command -v llama-cli) (prefer llama-completion on Homebrew b9290+)"
  else
    echo "llama=MISSING (local engine will report not found until installed)"
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
    if command -v llama-completion >/dev/null 2>&1; then
      echo "--- local-cli-smoke ---"
      PROMPT=$(mktemp)
      printf '%s' '<|im_start|>system
You translate text accurately and concisely. Output only the translation; no explanation.<|im_end|>
<|im_start|>user
英译简体中文。

hello<|im_end|>
<|im_start|>assistant
' > "$PROMPT"
      RAW=$(llama-completion -m "$FOUND" -f "$PROMPT" -n 24 -c 512 --temp 0 -ngl 99 -no-cnv --no-display-prompt 2>/dev/null || true)
      rm -f "$PROMPT"
      echo "cli_out=$RAW"
      echo "$RAW" | grep -qiE '你好|您好|哈喽|hello' && echo "cli_translate=PASS" || echo "cli_translate=CHECK"
    fi
  else
    echo "gguf=MISSING (download via onboarding or models/README.md)"
  fi
  echo "--- mac-logic-verify ---"
  python3 "$ROOT/tools/eval/mac-logic-verify.py"
  echo "--- mac-ocr-smoke ---"
  swift "$ROOT/tools/eval/mac-ocr-smoke.swift"
  echo "--- mac-e2e ---"
  bash "$ROOT/tools/eval/mac-e2e.sh"
  echo "RESULT=PASS"
} | tee "$LOG"
echo "wrote $LOG"
