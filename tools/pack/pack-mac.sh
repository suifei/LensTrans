#!/usr/bin/env bash
# Pack LensTrans macOS release into LensTrans.app.
#
# Default (bundled model): dist/macos/LensTrans.app — includes one selected GGUF (≤ 2.2 GB).
# Slim base (no GGUF):     bash tools/pack/pack-mac.sh --base → dist/macos-base/ (≤ ~30 MB intent).
#
# GGUF is NEVER committed to git; copied at pack time from models/ or Application Support.
# Metal llama.cpp dylibs go to Contents/Frameworks/ (in-process) + Resources/bin (CLI fallback).
#
# Usage:
#   bash tools/pack/pack-mac.sh              # default: bundled GGUF
#   bash tools/pack/pack-mac.sh --offline    # alias of default
#   bash tools/pack/pack-mac.sh --base       # no GGUF
#   bash tools/pack/pack-mac.sh --skip-build
#   CODESIGN_IDENTITY="Developer ID Application: …" bash tools/pack/pack-mac.sh --sign
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NAME=qwen2.5-1.5b-instruct-q4_k_m.gguf
EXPECTED_BYTES=1117320736
LIMIT_BASE=30000000
LIMIT_OFF=2200000000
SKIP_BUILD=0
DO_SIGN=0
DO_ZIP=1
# Default: ship with bundled GGUF (offline track).
BUNDLE_GGUF=1
OUT_ROOT="${OUT_ROOT:-$ROOT/dist/macos}"
BIN_SRC="$ROOT/mac/.build/release/LensTrans"
PLIST_SRC="$ROOT/mac/Info.plist"
LLAMA_BIN="$ROOT/third_party/llama.cpp/build/bin"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --sign) DO_SIGN=1 ;;
    --no-zip) DO_ZIP=0 ;;
    --offline) BUNDLE_GGUF=1; OUT_ROOT="${OUT_ROOT_OFFLINE:-$ROOT/dist/macos}" ;;
    --base) BUNDLE_GGUF=0; OUT_ROOT="${OUT_ROOT_BASE:-$ROOT/dist/macos-base}" ;;
    -h|--help)
      sed -n '2,16p' "$0"
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

APP="$OUT_ROOT/LensTrans.app"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "--- swift build -c release ---"
  if [[ ! -f "$LLAMA_BIN/libllama.dylib" ]]; then
    echo "NOTE: libllama.dylib missing — run: bash tools/fetch/fetch-llama-cpp.sh" >&2
    echo "      building without LENSTRANS_WITH_LLAMA (CLI fallback only)" >&2
  fi
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

GGUF_SRC="${LENSTRANS_GGUF_PATH:-}"
if [[ "$BUNDLE_GGUF" -eq 1 ]]; then
  if [[ -n "$GGUF_SRC" && ! -f "$GGUF_SRC" ]]; then
    echo "LENSTRANS_GGUF_PATH is not a file: $GGUF_SRC" >&2
    exit 1
  fi
  if [[ -z "$GGUF_SRC" ]]; then
    for c in \
      "$ROOT/models/$NAME" \
      "$HOME/Library/Application Support/LensTrans/models/$NAME"; do
      if [[ -f "$c" ]]; then GGUF_SRC="$c"; break; fi
    done
  fi
  if [[ -z "$GGUF_SRC" ]]; then
    echo "bundled pack needs $NAME — run: bash tools/fetch/fetch-gguf.sh" >&2
    echo "(or place file under models/; GGUF is gitignored, not committed)" >&2
    exit 1
  fi
  NAME=$(basename "$GGUF_SRC")
  SZ=$(stat -f%z "$GGUF_SRC")
  if [[ "$NAME" == "qwen2.5-1.5b-instruct-q4_k_m.gguf" && "$SZ" != "$EXPECTED_BYTES" ]]; then
    echo "GGUF size $SZ != $EXPECTED_BYTES" >&2
    exit 1
  fi
fi

copy_llama_dylibs() {
  local dest="$1"
  mkdir -p "$dest"
  # Regular files first, then recreate symlinks (loader-facing .0 / unversioned).
  find "$LLAMA_BIN" -maxdepth 1 -type f -name 'lib*.dylib' -exec cp -f {} "$dest/" \;
  while IFS= read -r link; do
    local base target
    base=$(basename "$link")
    target=$(readlink "$link")
    ln -sfn "$target" "$dest/$base"
  done < <(find "$LLAMA_BIN" -maxdepth 1 -type l -name 'lib*.dylib')
}

stage_app() {
  local dest_app="$1"
  echo "--- stage $dest_app ---"
  rm -rf "$dest_app"
  mkdir -p "$dest_app/Contents/MacOS" \
           "$dest_app/Contents/Resources" \
           "$dest_app/Contents/Frameworks"

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

  # In-process Metal: Frameworks next to MacOS (@executable_path/../Frameworks).
  if [[ -d "$LLAMA_BIN" ]] && [[ -f "$LLAMA_BIN/libllama.dylib" ]]; then
    copy_llama_dylibs "$dest_app/Contents/Frameworks"
  fi

  # CLI fallback: third_party llama-completion (+ same dylibs under Resources/bin).
  local tp_bin=""
  for c in \
    "$LLAMA_BIN/llama-completion" \
    "$LLAMA_BIN/llama-cli"; do
    if [[ -x "$c" ]]; then tp_bin="$c"; break; fi
  done
  if [[ -n "$tp_bin" ]]; then
    mkdir -p "$dest_app/Contents/Resources/bin"
    local rbin="$dest_app/Contents/Resources/bin"
    cp -f "$tp_bin" "$rbin/$(basename "$tp_bin")"
    chmod +x "$rbin/"*
    copy_llama_dylibs "$rbin"
  fi

  if [[ "$BUNDLE_GGUF" -eq 1 && -n "$GGUF_SRC" ]]; then
    mkdir -p "$dest_app/Contents/Resources/models"
    cp -f "$GGUF_SRC" "$dest_app/Contents/Resources/models/$NAME"
    if [[ -f "$ROOT/tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt" ]]; then
      cp -f "$ROOT/tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt" \
        "$dest_app/Contents/Resources/models/Qwen2.5-Instruct-LICENSE.txt"
    fi
  fi

  cat > "$dest_app/Contents/Resources/README.txt" <<EOF
LensTrans macOS app bundle.
Default pack: Resources/models/$NAME bundled (gitignored; copied at pack time).
Slim pack (--base): no GGUF — download via onboarding or fetch-gguf.sh --to-app-support.
Local engine: in-process Metal llama.cpp when linked; CLI fallback in Resources/bin.
EOF
}

stage_app "$APP"

if [[ "$BUNDLE_GGUF" -eq 0 ]]; then
  if find "$APP" -name '*.gguf' | grep -q .; then
    echo "GGUF leaked into --base app bundle" >&2
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
echo "app=$APP bundled_gguf=$BUNDLE_GGUF"

if [[ "$BUNDLE_GGUF" -eq 0 && "$APP_BYTES" -gt "$LIMIT_BASE" ]]; then
  if find "$APP" -name '*.gguf' | grep -q .; then
    echo "base pack exceeds 30MB and contains GGUF — FAIL" >&2
    exit 1
  fi
  echo "NOTE: base app_approx_bytes=$APP_BYTES > 30e6 (CLI/dylibs); GGUF absent OK"
fi

if [[ "$BUNDLE_GGUF" -eq 1 ]]; then
  if [[ "$APP_BYTES" -gt "$LIMIT_OFF" ]]; then
    echo "offline/bundled pack $APP_BYTES exceeds 2.2GB" >&2
    exit 1
  fi
  echo "bundled GGUF limit 2.2GB: PASS ($APP_BYTES)"
  if [[ ! -f "$APP/Contents/Resources/models/$NAME" ]]; then
    echo "missing bundled model in Resources/models/" >&2
    exit 1
  fi
fi

if [[ "$DO_ZIP" -eq 1 ]]; then
  if [[ "$BUNDLE_GGUF" -eq 1 ]]; then
    ZIP="$OUT_ROOT/LensTrans-macos.zip"
  else
    ZIP="$OUT_ROOT/LensTrans-macos-base.zip"
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
  echo "- track: $([[ "$BUNDLE_GGUF" -eq 1 ]] && echo bundled-gguf || echo base)"
  echo "- app: \`$APP\`"
  echo "- binary_bytes: $BIN_BYTES"
  echo "- app_approx_bytes: $APP_BYTES"
  echo "- GGUF in bundle: $([[ "$BUNDLE_GGUF" -eq 1 ]] && echo yes || echo no)"
  echo "- in-process Metal Frameworks: $([[ -f "$APP/Contents/Frameworks/libllama.dylib" ]] && echo yes || echo no)"
  echo "- Developer ID / notarization: not performed (script reserved --sign)"
} > "$REPORT"
echo "wrote $REPORT"

echo "RESULT=PASS"
echo "install: bash tools/pack/install-mac.sh$([[ "$BUNDLE_GGUF" -eq 0 ]] && echo ' --base' || true)"
echo "run:     bash tools/run/run-mac.sh"
echo "e2e:     \"$APP/Contents/MacOS/LensTrans\" --e2e --e2e-sec 8 --no-onboard"
