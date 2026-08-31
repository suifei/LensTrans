#!/usr/bin/env bash
# Real-desktop macOS acceptance: fixed TextEdit fixture + fixed signed App.
# This intentionally starts the normal accessory app, not --e2e, and checks the
# capture -> Vision -> Metal -> Core layout -> NSPanel path from its runtime log.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="${LENSTRANS_E2E_APP:-$ROOT/dist/e2e/LensTrans.app}"
BIN="$APP/Contents/MacOS/LensTrans"
FIXTURE="$ROOT/tools/eval/fixtures/mac-desktop.txt"
LOG="${LENSTRANS_RUNTIME_LOG_PATH:-/private/tmp/lenstrans-runtime-desktop.log}"
SHOT="${LENSTRANS_RUNTIME_SCREENSHOT:-$ROOT/tools/eval/out/mac-runtime-desktop.png}"

if [[ ! -x "$BIN" ]]; then
  echo "runtime-desktop-e2e status=BLOCKED reason=packaged app missing path=$APP" >&2
  exit 3
fi
if [[ ! -f "$FIXTURE" ]]; then
  echo "runtime-desktop-e2e status=FAIL reason=fixture missing path=$FIXTURE" >&2
  exit 4
fi

while read -r pid; do
  [[ -z "$pid" || "$pid" == "$$" ]] || kill "$pid" 2>/dev/null || true
done < <(pgrep -f -- "$BIN" 2>/dev/null || true)
: > "$LOG"
open -a TextEdit "$FIXTURE"
sleep 2
osascript -e 'tell application "TextEdit" to activate' 2>/dev/null || true
osascript -e 'tell application "System Events" to tell process "TextEdit" to set position of window "mac-desktop.txt" to {2170, -900}' 2>/dev/null || true

env LENSTRANS_VISUAL_TEST=1 LENSTRANS_RUNTIME_LOG=1 \
  LENSTRANS_FORCE_CONTRAST=0 \
  LENSTRANS_START_DISPLAY_ID="${LENSTRANS_START_DISPLAY_ID:-2}" \
  LENSTRANS_START_RECT="${LENSTRANS_START_RECT:-2170,1824,480,320}" \
  "$BIN" --no-onboard --start-watching >"$LOG" 2>&1 &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true' EXIT

deadline=$((SECONDS + 30))
while (( SECONDS < deadline )); do
  if grep -q 'present.committed' "$LOG"; then break; fi
  sleep 1
done

# One diagnostic screenshot is enough for visual QA; product capture uses SCKit,
# so this test does not exercise repeated screenshot capture.
screencapture -x -D 1 "$SHOT" 2>/dev/null || true
screencapture -x -D 2 "${SHOT%.png}-display2.png" 2>/dev/null || true

if ! grep -q 'capture.ready' "$LOG"; then
  echo "runtime-desktop-e2e status=FAIL reason=capture-not-started log=$LOG" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi
if ! grep -q 'ocr.blocks=[1-9].*Hello LensTrans' "$LOG"; then
  echo "runtime-desktop-e2e status=FAIL reason=target-ocr-missing log=$LOG" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi
if ! grep -q 'translate.results=.*你好，镜头。' "$LOG" || \
   ! grep -q 'translate.results=.*这是第二行用于视觉OCR测试的线。' "$LOG"; then
  echo "runtime-desktop-e2e status=FAIL reason=target-translation-missing log=$LOG" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi
if ! grep -q 'present.committed blocks=[2-9]' "$LOG"; then
  echo "runtime-desktop-e2e status=FAIL reason=translation-not-present log=$LOG" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

echo "runtime-desktop-e2e status=PASS app=$APP fixture=$FIXTURE log=$LOG screenshot=$SHOT"
tail -80 "$LOG"
