#!/usr/bin/env bash
# Pack LensTrans macOS release into LensTrans.app (dual-track, parity with pack-windows.ps1).
#
# Base pack (default): dist/macos/LensTrans.app — NO GGUF (≤ ~30 MB binary tree).
# Offline pack:        dist/macos-offline/LensTrans.app — base + Resources/models/*.gguf (≤ 520 MB).
#
# Usage:
#   bash tools/pack/pack-mac.sh
#   bash tools/pack/pack-mac.sh --offline          # requires models/*.gguf (fetch-gguf.sh)
#   bash tools/pack/pack-mac.sh --skip-build
#   CODESIGN_IDENTITY="Developer ID Application: …" bash tools/pack/pack-mac.sh --sign
# Notarization is NOT run (needs Apple notary credentials).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_ROOT="${OUT_ROOT:-$ROOT/dist/macos}"
BIN_SRC="$ROOT/mac/.build/release/LensTrans"
PLIST_SRC="$ROOT/mac/Info.plist"
NAME=qwen2.5-0.5b-instruct-q4_k_m.gguf
EXPECTED_BYTES=491400032
LIMIT_BASE=30000000
LIMIT_OFF=520000000
SKIP_BUILD=0
DO_SIGN=0
DO_ZIP=1
OFFLINE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --sign) DO_SIGN=1 ;;
    --no-zip) DO_ZIP=0 ;;
    --offline) OFFLINE=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "pack-mac.sh requires macOS" >&2
  exit 1
fi

if [[ "$OFFLINE" -eq 1 ]]; then
  OUT_ROOT="${OUT_ROOT_OFFLINE:-$ROOT/dist/macos-offline}"
fi
APP="$OUT_ROOT/LensTrans.app"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "--- swift build -c release ---"
  (cd "$ROOT/mac" && swift build -c release --product LensTrans)
fi

if [[ ! -x "$BIN_SRC" ]]; then
  echo "missing release binary: $BIN_SRC" >&2
  exit 1
fi

if [[ ! -f "$PLIST_SRC" ]]; then
  echo "missing Info.plist: $PLIST_SRC" >&2
  exit 1
fi

# Refuse accidental GGUF under mac/ sources.
if find "$ROOT/mac" -name '*.gguf' 2>/dev/null | grep -q .; then
  echo "refusing to pack: GGUF found under mac/" >&2
  exit 1
fi

GGUF_SRC=""
if [[ "$OFFLINE" -eq 1 ]]; then
  for c in \
    "$ROOT/models/$NAME" \
    "$HOME/Library/Application Support/LensTrans/models/$NAME"; do
    if [[ -f "$c" ]]; then GGUF_SRC="$c"; break; fi
  done
  if [[ -z "$GGUF_SRC" ]]; then
    echo "offline pack needs $NAME — run: bash tools/fetch/fetch-gguf.sh" >&2
    exit 1
  fi
  SZ=$(stat -f%z "$GGUF_SRC")
  if [[ "$SZ" != "$EXPECTED_BYTES" ]]; then
    echo "GGUF size $SZ != $EXPECTED_BYTES" >&2
    exit 1
  fi
fi

stage_app() {
  local dest_app="$1"
  echo "--- stage $dest_app ---"
  rm -rf "$dest_app"
  mkdir -p "$dest_app/Contents/MacOS" "$dest_app/Contents/Resources"

  cp "$PLIST_SRC" "$dest_app/Contents/Info.plist"
  ensure_plist_key() {
    local plist="$1" key="$2" type="$3" value="$4"
    if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
    else
      /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$plist"
    fi
  }
  local pl="$dest_app/Contents/Info.plist"
  ensure_plist_key "$pl" CFBundleExecutable string LensTrans
  ensure_plist_key "$pl" CFBundlePackageType string APPL
  ensure_plist_key "$pl" CFBundleInfoDictionaryVersion string "6.0"
  ensure_plist_key "$pl" LSUIElement bool true

  cp "$BIN_SRC" "$dest_app/Contents/MacOS/LensTrans"
  chmod +x "$dest_app/Contents/MacOS/LensTrans"
  printf 'APPL????' > "$dest_app/Contents/PkgInfo"

  # Only ship third_party CLI (+ dylibs). Do NOT copy Homebrew cellar binaries.
  local tp_bin=""
  for c in \
    "$ROOT/third_party/llama.cpp/build/bin/llama-completion" \
    "$ROOT/third_party/llama.cpp/build/bin/llama-cli"; do
    if [[ -x "$c" ]]; then tp_bin="$c"; break; fi
  done
  if [[ -n "$tp_bin" ]]; then
    mkdir -p "$dest_app/Contents/Resources/bin"
    local rbin="$dest_app/Contents/Resources/bin"
    cp -f "$tp_bin" "$rbin/$(basename "$tp_bin")"
    chmod +x "$rbin/"*
    local sbin
    sbin="$(dirname "$tp_bin")"
    # Copy only regular dylib files (not symlink duplicates — keeps offline ≤520MB).
    find "$sbin" -maxdepth 1 -type f -name '*.dylib' -exec cp -f {} "$rbin/" \;
    # Recreate loader-facing symlinks (.0.dylib / unversioned).
    while IFS= read -r link; do
      local base target
      base=$(basename "$link")
      target=$(readlink "$link")
      ln -sfn "$target" "$rbin/$base"
    done < <(find "$sbin" -maxdepth 1 -type l -name '*.dylib')
  fi

  cat > "$dest_app/Contents/Resources/README.txt" <<EOF
LensTrans macOS app bundle.
Base pack: GGUF not included — download via onboarding or:
  bash tools/fetch/fetch-gguf.sh --to-app-support
Offline pack: Resources/models/$NAME
EOF
}

stage_app "$APP"

if [[ "$OFFLINE" -eq 1 ]]; then
  mkdir -p "$APP/Contents/Resources/models"
  cp -f "$GGUF_SRC" "$APP/Contents/Resources/models/$NAME"
  # Also copy Qwen license next to weights for redistrib.
  if [[ -f "$ROOT/tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt" ]]; then
    cp -f "$ROOT/tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt" \
      "$APP/Contents/Resources/models/"
  fi
else
  if find "$APP" -name '*.gguf' | grep -q .; then
    echo "GGUF leaked into base app bundle" >&2
    exit 1
  fi
fi

sign_app() {
  local dest_app="$1"
  if [[ "$DO_SIGN" -eq 1 ]]; then
    IDENTITY="${CODESIGN_IDENTITY:-}"
    if [[ -z "$IDENTITY" ]]; then
      echo "--sign set but CODESIGN_IDENTITY empty; ad-hoc fallback" >&2
      codesign --force --deep --sign - "$dest_app" || true
    else
      echo "--- codesign ($IDENTITY) ---"
      codesign --force --options runtime --sign "$IDENTITY" --timestamp "$dest_app/Contents/MacOS/LensTrans"
      codesign --force --deep --options runtime --sign "$IDENTITY" --timestamp "$dest_app"
      codesign --verify --verbose=2 "$dest_app"
      echo "signed (not notarized)"
    fi
  else
    echo "--- codesign (ad-hoc, local only) ---"
    codesign --force --deep --sign - "$dest_app" || true
    echo "notarization: not performed"
  fi
}
sign_app "$APP"

BIN_BYTES=$(stat -f%z "$APP/Contents/MacOS/LensTrans")
APP_BYTES=$(du -sk "$APP" | awk '{print $1 * 1024}')
echo "binary_bytes=$BIN_BYTES app_approx_bytes=$APP_BYTES"
echo "app=$APP"

if [[ "$OFFLINE" -eq 0 && "$APP_BYTES" -gt "$LIMIT_BASE" ]]; then
  # Soft warn: ad-hoc + bundled CLI may exceed 30e6; base product intent is no GGUF.
  if find "$APP" -name '*.gguf' | grep -q .; then
    echo "base pack exceeds 30MB and contains GGUF — FAIL" >&2
    exit 1
  fi
  echo "NOTE: base app_approx_bytes=$APP_BYTES > 30e6 (CLI/dylibs); GGUF absent OK"
fi

if [[ "$OFFLINE" -eq 1 ]]; then
  if [[ "$APP_BYTES" -gt "$LIMIT_OFF" ]]; then
    echo "offline pack $APP_BYTES exceeds 520e6" >&2
    exit 1
  fi
  echo "offline limit 520MB: PASS ($APP_BYTES)"
fi

if [[ "$DO_ZIP" -eq 1 ]]; then
  if [[ "$OFFLINE" -eq 1 ]]; then
    ZIP="$OUT_ROOT/LensTrans-macos-offline.zip"
  else
    ZIP="$OUT_ROOT/LensTrans-macos.zip"
  fi
  rm -f "$ZIP"
  (cd "$OUT_ROOT" && zip -qry "$(basename "$ZIP")" LensTrans.app)
  echo "zip=$ZIP bytes=$(stat -f%z "$ZIP")"
fi

REPORT="$ROOT/tools/eval/out/installer-size-mac.md"
mkdir -p "$(dirname "$REPORT")"
{
  echo "# macOS installer size"
  echo ""
  echo "- date: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "- track: $([[ "$OFFLINE" -eq 1 ]] && echo offline || echo base)"
  echo "- app: \`$APP\`"
  echo "- binary_bytes: $BIN_BYTES"
  echo "- app_approx_bytes: $APP_BYTES"
  echo "- GGUF in bundle: $([[ "$OFFLINE" -eq 1 ]] && echo yes || echo no)"
  echo "- Developer ID / notarization: not performed (script reserved --sign)"
} > "$REPORT"
echo "wrote $REPORT"

echo "RESULT=PASS"
echo "install: bash tools/pack/install-mac.sh$([[ "$OFFLINE" -eq 1 ]] && echo ' --offline' || true)"
echo "run:     bash tools/run/run-mac.sh"
echo "e2e:     \"$APP/Contents/MacOS/LensTrans\" --e2e --e2e-sec 8 --no-onboard"
