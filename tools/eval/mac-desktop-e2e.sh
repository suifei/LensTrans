#!/usr/bin/env bash
# Fixed-path packaged-app E2E. Grant Screen Recording to this app once; subsequent
# builds keep the same path, bundle id and signing identity.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_ROOT="$ROOT/dist/e2e"
APP="$OUT_ROOT/LensTrans.app"
IDENTITY="${LENSTRANS_E2E_CODESIGN_IDENTITY:-}"

if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(bash "$ROOT/tools/pack/ensure-mac-e2e-identity.sh")
fi
if [[ -z "$IDENTITY" ]]; then
  echo "No stable code-signing identity found." >&2
  echo "Set LENSTRANS_E2E_CODESIGN_IDENTITY to a persistent local identity." >&2
  exit 2
fi

echo "fixed_app=$APP"
echo "codesign_identity=$IDENTITY"
OUT_ROOT="$OUT_ROOT" CODESIGN_IDENTITY="$IDENTITY" \
  bash "$ROOT/tools/pack/pack-mac.sh" --sign --no-zip

LENSTRANS_APP_PATH="$APP" \
LENSTRANS_E2E_REPORT="$ROOT/tools/eval/out/mac-desktop-e2e.md" \
  bash "$ROOT/tools/eval/mac-e2e.sh" --app --e2e-llama --require-screen-capture
