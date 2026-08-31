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
osascript -e 'tell application "System Events" to key code 123 using {command down}' 2>/dev/null || true

env LENSTRANS_VISUAL_TEST=1 LENSTRANS_RUNTIME_LOG=1 \
  LENSTRANS_FORCE_CONTRAST=0 \
  LENSTRANS_START_DISPLAY_ID="${LENSTRANS_START_DISPLAY_ID:-2}" \
  LENSTRANS_START_RECT="${LENSTRANS_START_RECT:-2170,1824,480,320}" \
  "$BIN" --no-onboard --start-watching >"$LOG" 2>&1 &
APP_PID=$!
trap 'kill "$APP_PID" 2>/dev/null || true' EXIT

deadline=$((SECONDS + 60))
while (( SECONDS < deadline )); do
  if grep -Eq 'batch\.usable=[1-9][0-9]*/[1-9][0-9]*' "$LOG" && \
     grep -Eq 'present.committed blocks=([3-9]|[1-9][0-9]+)' "$LOG"; then break; fi
  sleep 1
done

# One diagnostic screenshot is enough for visual QA; product capture uses SCKit,
# so this test does not exercise repeated screenshot capture.
if ! screencapture -x -D 1 "$SHOT" 2>/dev/null; then
  echo "runtime-desktop-e2e status=FAIL reason=primary-screenshot-failed" >&2
  exit 1
fi
DISPLAY2_SHOT="${SHOT%.png}-display2.png"
if ! screencapture -x -D 2 "$DISPLAY2_SHOT" 2>/dev/null; then
  echo "runtime-desktop-e2e status=FAIL reason=target-screenshot-failed" >&2
  exit 1
fi
if ! xcrun swift "$ROOT/tools/eval/mac-runtime-screenshot-check.swift" "$DISPLAY2_SHOT"; then
  echo "runtime-desktop-e2e status=FAIL reason=overlay-not-visible-in-screenshot" >&2
  exit 1
fi

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
if ! grep -Eq 'batch\.usable=[1-9][0-9]*/[1-9][0-9]*' "$LOG"; then
  echo "runtime-desktop-e2e status=FAIL reason=batch-translation-unusable log=$LOG" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi
if ! grep -Eq '((^|:)[0-9]+|<sn>[0-9]+)\|\|\|.*[一-龥]' "$LOG"; then
  echo "runtime-desktop-e2e status=FAIL reason=batch-output-has-no-chinese log=$LOG" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi
if ! grep -q 'model.prewarm ready=true' "$LOG"; then
  echo "runtime-desktop-e2e status=FAIL reason=model-not-prewarmed log=$LOG" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi
if awk -F'fontPhysicalPx=' '/fontPhysicalPx=/{ if (($2 + 0) > 20.5) bad=1 } END{ exit bad }' "$LOG"; then
  :
else
  echo "runtime-desktop-e2e status=FAIL reason=physical-font-cap-exceeded log=$LOG" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi
if ! grep -Eq 'present.committed blocks=([3-9]|[1-9][0-9]+)' "$LOG"; then
  echo "runtime-desktop-e2e status=FAIL reason=translation-not-present log=$LOG" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

echo "runtime-desktop-e2e status=PASS app=$APP fixture=$FIXTURE log=$LOG screenshot=$SHOT"
tail -80 "$LOG"
