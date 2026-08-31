#!/usr/bin/env bash
# Download official Qwen2.5-0.5B Instruct Q4_K_M GGUF with resume (-C -).
# Prefer ModelScope (domestic). Do NOT rely on Hugging Face direct.
# Verifies size + SHA256 against model_meta / ModelMetaLogic.
# Never commits the file (gitignores *.gguf).
#
# Usage:
#   bash tools/fetch/fetch-gguf.sh
#   bash tools/fetch/fetch-gguf.sh --to-app-support
#   bash tools/fetch/fetch-gguf.sh --verify-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tools/fetch/_proxy.sh
source "$(dirname "$0")/_proxy.sh"

NAME=qwen2.5-0.5b-instruct-q4_k_m.gguf
EXPECTED_BYTES=491400032
EXPECTED_SHA=74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db
# Domestic first (ModelScope). HF listed only as last-resort via proxy — not required.
URL_MS="https://www.modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/${NAME}"
URL_HF="https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/${NAME}"
DEST="$ROOT/models/$NAME"
APP_SUPPORT="$HOME/Library/Application Support/LensTrans/models/$NAME"
TO_APP=0
VERIFY_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to-app-support) TO_APP=1 ;;
    --verify-only) VERIFY_ONLY=1 ;;
    --dest)
      DEST="$2"; shift
      ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$(dirname "$DEST")"

verify_file() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  local sz
  sz=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f")
  if [[ "$sz" != "$EXPECTED_BYTES" ]]; then
    echo "size mismatch: $f has $sz want $EXPECTED_BYTES" >&2
    return 1
  fi
  local got
  got=$(shasum -a 256 "$f" | awk '{print $1}' | tr 'A-Z' 'a-z')
  if [[ "$got" != "$EXPECTED_SHA" ]]; then
    echo "sha256 mismatch: $f got $got want $EXPECTED_SHA" >&2
    return 1
  fi
  echo "verify OK: $f ($EXPECTED_BYTES bytes, sha256=$EXPECTED_SHA)"
  return 0
}

# Prefer existing good copies (App Support / models / sibling).
for cand in "$DEST" "$APP_SUPPORT" \
  "$HOME/works/LensTrans/models/$NAME"; do
  if verify_file "$cand" 2>/dev/null; then
    if [[ "$cand" != "$DEST" ]]; then
      echo "--- reuse $cand → $DEST ---"
      mkdir -p "$(dirname "$DEST")"
      if [[ ! -f "$DEST" ]]; then
        ln "$cand" "$DEST" 2>/dev/null || cp -f "$cand" "$DEST"
      fi
      verify_file "$DEST"
    fi
    if [[ "$TO_APP" -eq 1 ]]; then
      mkdir -p "$(dirname "$APP_SUPPORT")"
      if [[ ! -f "$APP_SUPPORT" ]]; then
        ln "$DEST" "$APP_SUPPORT" 2>/dev/null || cp -f "$DEST" "$APP_SUPPORT"
      fi
      verify_file "$APP_SUPPORT"
    fi
    echo "RESULT=PASS (already present)"
    exit 0
  fi
done

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
  echo "missing or invalid GGUF at $DEST" >&2
  exit 1
fi

PART="${DEST}.part"
curl_to_part() {
  local url="$1"
  curl -L -C - --retry 8 --retry-all-errors --fail \
    --connect-timeout 30 \
    -o "$PART" "$url"
}

set +e
echo "--- ModelScope (domestic, no HF) ---"
with_domestic_direct curl_to_part "$URL_MS"
RC=$?
if [[ $RC -ne 0 ]] || ! verify_file "$PART" 2>/dev/null; then
  echo "ModelScope incomplete; last-resort Hugging Face via local proxy (not direct)…"
  with_github_proxy curl_to_part "$URL_HF"
  RC=$?
fi
set -e

if ! verify_file "$PART"; then
  echo "download failed size/sha check" >&2
  exit 1
fi

mv -f "$PART" "$DEST"
verify_file "$DEST"

if [[ "$TO_APP" -eq 1 ]]; then
  mkdir -p "$(dirname "$APP_SUPPORT")"
  ln "$DEST" "$APP_SUPPORT" 2>/dev/null || cp -f "$DEST" "$APP_SUPPORT"
  verify_file "$APP_SUPPORT"
fi

echo "license: tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt"
echo "RESULT=PASS dest=$DEST"
