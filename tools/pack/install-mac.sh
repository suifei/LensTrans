#!/usr/bin/env bash
# Install staged LensTrans.app to /Applications or ~/Applications.
# Usage:
#   bash tools/pack/install-mac.sh              # default: dist/macos/ (bundled GGUF)
#   bash tools/pack/install-mac.sh --offline    # alias of default
#   bash tools/pack/install-mac.sh --base       # slim pack dist/macos-base/ (no GGUF)
#   bash tools/pack/install-mac.sh --user       # ~/Applications
# Does not notarize.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TRACK=bundled  # bundled | base
USER_ONLY=0
SRC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_ONLY=1 ;;
    --offline) TRACK=bundled ;;
    --base) TRACK=base ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$SRC" ]]; then
  if [[ "$TRACK" == "base" ]]; then
    SRC="$ROOT/dist/macos-base/LensTrans.app"
  else
    # Prefer current default; accept legacy macos-offline path.
    if [[ -d "$ROOT/dist/macos/LensTrans.app" ]]; then
      SRC="$ROOT/dist/macos/LensTrans.app"
    else
      SRC="$ROOT/dist/macos-offline/LensTrans.app"
    fi
  fi
fi

if [[ ! -d "$SRC" ]]; then
  echo "missing $SRC — run: bash tools/pack/pack-mac.sh$([[ "$TRACK" == base ]] && echo ' --base' || true)" >&2
  exit 1
fi

if [[ "$TRACK" == "base" ]]; then
  if find "$SRC" -name '*.gguf' | grep -q .; then
    echo "refusing to install --base track that contains GGUF" >&2
    exit 1
  fi
fi

if [[ -n "${DEST:-}" ]]; then
  DEST_DIR="$DEST"
elif [[ "$USER_ONLY" -eq 1 ]]; then
  DEST_DIR="$HOME/Applications"
else
  if [[ -w /Applications ]]; then
    DEST_DIR="/Applications"
  else
    DEST_DIR="$HOME/Applications"
  fi
fi

mkdir -p "$DEST_DIR"
TARGET="$DEST_DIR/LensTrans.app"
rm -rf "$TARGET"
cp -R "$SRC" "$TARGET"
echo "installed $TARGET"
echo "launch: open \"$TARGET\""
echo "or:     bash tools/run/run-mac.sh"
echo "cli:    \"$TARGET/Contents/MacOS/LensTrans\" --e2e --no-onboard"
echo "screen recording: System Settings → Privacy & Security → Screen Recording → enable LensTrans"
