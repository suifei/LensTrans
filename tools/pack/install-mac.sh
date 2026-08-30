#!/usr/bin/env bash
# Install staged LensTrans.app to /Applications or ~/Applications.
# Usage:
#   bash tools/pack/install-mac.sh              # base: dist/macos/LensTrans.app
#   bash tools/pack/install-mac.sh --offline    # offline pack (may contain GGUF)
#   bash tools/pack/install-mac.sh --user       # ~/Applications
# Does not notarize. Base track refuses GGUF in the source tree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OFFLINE=0
USER_ONLY=0
SRC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) USER_ONLY=1 ;;
    --offline) OFFLINE=1 ;;
    -h|--help)
      sed -n '2,9p' "$0"
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
  if [[ "$OFFLINE" -eq 1 ]]; then
    SRC="$ROOT/dist/macos-offline/LensTrans.app"
  else
    SRC="${SRC:-$ROOT/dist/macos/LensTrans.app}"
  fi
fi

if [[ ! -d "$SRC" ]]; then
  echo "missing $SRC — run: bash tools/pack/pack-mac.sh$([[ "$OFFLINE" -eq 1 ]] && echo ' --offline')" >&2
  exit 1
fi

if [[ "$OFFLINE" -eq 0 ]]; then
  if find "$SRC" -name '*.gguf' | grep -q .; then
    echo "refusing to install base track that contains GGUF (use --offline)" >&2
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
