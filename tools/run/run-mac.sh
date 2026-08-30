#!/usr/bin/env bash
# One-shot: ensure GGUF + (optional) llama.cpp, build/pack, launch LensTrans local engine.
#
# Usage:
#   bash tools/run/run-mac.sh                 # tray app, skip onboard if settings exist
#   bash tools/run/run-mac.sh --e2e           # automated gate
#   bash tools/run/run-mac.sh --fetch-llama   # also build third_party llama.cpp b10688
#   bash tools/run/run-mac.sh --no-pack       # run .build/release binary instead of .app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FETCH_LLAMA=0
DO_PACK=1
E2E=0
EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fetch-llama) FETCH_LLAMA=1 ;;
    --no-pack) DO_PACK=0 ;;
    --e2e) E2E=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) EXTRA+=("$1") ;;
  esac
  shift
done

echo "=== 1) GGUF (resume + SHA) ==="
bash "$ROOT/tools/fetch/fetch-gguf.sh" --to-app-support

if [[ "$FETCH_LLAMA" -eq 1 ]]; then
  echo "=== 2) llama.cpp b10688 ==="
  bash "$ROOT/tools/fetch/fetch-llama-cpp.sh"
elif command -v llama-completion >/dev/null 2>&1; then
  echo "=== 2) llama-completion=$(command -v llama-completion) ==="
elif [[ -x "$ROOT/third_party/llama.cpp/build/bin/llama-cli" ]]; then
  echo "=== 2) third_party llama-cli OK ==="
else
  echo "=== 2) no local CLI yet — will try PATH at runtime; optional: --fetch-llama or brew install llama.cpp ==="
fi

echo "=== 3) build ==="
(cd "$ROOT/mac" && swift build -c release --product LensTrans)

BIN="$ROOT/mac/.build/release/LensTrans"
if [[ "$DO_PACK" -eq 1 ]]; then
  echo "=== 4) pack .app ==="
  bash "$ROOT/tools/pack/pack-mac.sh" --skip-build --no-zip
  BIN="$ROOT/dist/macos/LensTrans.app/Contents/MacOS/LensTrans"
fi

echo "=== 5) launch ($BIN) ==="
if [[ "$E2E" -eq 1 ]]; then
  exec "$BIN" --e2e --e2e-sec 8 --no-onboard --e2e-llama "${EXTRA[@]}"
fi
exec "$BIN" --no-onboard "${EXTRA[@]}"
