#!/usr/bin/env bash
# Clone + build pinned llama.cpp b10688 under third_party/ (not vendored in git).
# macOS: Metal ON, produce llama-cli (+ shared libs) under build/bin.
# GitHub clone PREFERS local HTTP proxy (see tools/fetch/_proxy.sh).
#
# Usage:
#   bash tools/fetch/fetch-llama-cpp.sh
#   bash tools/fetch/fetch-llama-cpp.sh --skip-clone
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=tools/fetch/_proxy.sh
source "$(dirname "$0")/_proxy.sh"

LLAMA_SRC="$ROOT/third_party/llama.cpp"
TAG=b10688
COMMIT=c589f0ed10c643678c4707dd160c21ac7633ebc0
REMOTE=https://github.com/ggml-org/llama.cpp.git
SKIP_CLONE=0
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-clone) SKIP_CLONE=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This helper targets macOS. On Windows use third_party/README.md batch steps." >&2
  exit 1
fi

mkdir -p "$ROOT/third_party"

clone_once() {
  # HTTP/1.1 reduces intermittent HTTP/2 CANCEL on flaky links.
  git -c http.version=HTTP/1.1 -c http.postBuffer=524288000 \
    clone --depth 1 --branch "$TAG" "$REMOTE" "$LLAMA_SRC"
}

if [[ "$SKIP_CLONE" -eq 0 ]]; then
  if [[ -d "$LLAMA_SRC/.git" ]]; then
    echo "--- existing clone; checking pin ---"
    cur="$(git -C "$LLAMA_SRC" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$cur" != "$COMMIT" ]]; then
      echo "WARNING: HEAD=$cur expected=$COMMIT — re-cloning pinned tag $TAG"
      rm -rf "$LLAMA_SRC"
    fi
  fi
  if [[ ! -d "$LLAMA_SRC/.git" ]]; then
    echo "--- git clone llama.cpp $TAG (GitHub → proxy first) ---"
    rm -rf "$LLAMA_SRC"
    ok=0
    for attempt in 1 2 3; do
      echo "clone attempt $attempt/3"
      if with_github_proxy clone_once; then
        ok=1
        break
      fi
      rm -rf "$LLAMA_SRC"
      sleep $((attempt * 2))
    done
    if [[ "$ok" -ne 1 ]]; then
      echo "ERROR: failed to clone llama.cpp $TAG after 3 attempts" >&2
      echo "Fallback: brew install llama.cpp  # use llama-completion on PATH" >&2
      exit 1
    fi
  fi
  cur="$(git -C "$LLAMA_SRC" rev-parse HEAD)"
  echo "llama.cpp HEAD=$cur (pin $COMMIT / $TAG)"
  if [[ "$cur" != "$COMMIT" ]]; then
    echo "ERROR: tag $TAG did not resolve to locked commit $COMMIT" >&2
    exit 1
  fi
fi

if [[ ! -f "$LLAMA_SRC/include/llama.h" && ! -f "$LLAMA_SRC/llama.h" ]]; then
  echo "missing llama headers under $LLAMA_SRC" >&2
  exit 1
fi

BUILD="$LLAMA_SRC/build"
echo "--- cmake configure (Metal) ---"
cmake -S "$LLAMA_SRC" -B "$BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_METAL=ON \
  -DBUILD_SHARED_LIBS=ON \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_EXAMPLES=ON \
  2>&1 | tee /tmp/lenstrans-llama-cmake.log | tail -40

echo "--- cmake build ---"
set +e
# Prefer llama-completion (Mac engine); then llama-cli / main; else lib only.
cmake --build "$BUILD" --config Release -j"$JOBS" --target llama-completion 2>/tmp/lenstrans-llama-build.err
RC=$?
if [[ $RC -ne 0 ]]; then
  cmake --build "$BUILD" --config Release -j"$JOBS" --target llama-cli 2>>/tmp/lenstrans-llama-build.err
  RC=$?
fi
if [[ $RC -ne 0 ]]; then
  cmake --build "$BUILD" --config Release -j"$JOBS" --target main 2>>/tmp/lenstrans-llama-build.err
  RC=$?
fi
if [[ $RC -ne 0 ]]; then
  cmake --build "$BUILD" --config Release -j"$JOBS" --target llama
  RC=$?
fi
set -e
if [[ $RC -ne 0 ]]; then
  echo "llama.cpp build failed; see /tmp/lenstrans-llama-build.err" >&2
  exit 1
fi

BIN_DIR="$BUILD/bin"
mkdir -p "$BIN_DIR"
# Normalize: ensure llama-cli name if only main/completion exists.
if [[ ! -x "$BIN_DIR/llama-cli" ]]; then
  for c in \
    "$BIN_DIR/llama-completion" \
    "$BUILD/bin/llama-cli" \
    "$BUILD/examples/main/llama-cli" \
    "$BUILD/examples/main/main" \
    "$BUILD/bin/main"; do
    if [[ -x "$c" ]]; then
      if [[ "$(basename "$c")" == "llama-completion" ]]; then
        : # keep as-is; Engine prefers llama-completion
      else
        cp -f "$c" "$BIN_DIR/llama-cli"
      fi
      break
    fi
  done
fi

echo "--- artifacts ---"
ls -la "$BIN_DIR" 2>/dev/null || true
find "$BUILD" \( -name 'libllama*' -o -name 'libggml*' \) 2>/dev/null | head -20 || true

if [[ -x "$BIN_DIR/llama-completion" ]]; then
  echo "RESULT=PASS cli=$BIN_DIR/llama-completion"
elif [[ -x "$BIN_DIR/llama-cli" ]]; then
  echo "RESULT=PASS cli=$BIN_DIR/llama-cli"
elif command -v llama-completion >/dev/null 2>&1; then
  echo "RESULT=PASS (lib built; runtime can use Homebrew llama-completion)"
else
  echo "RESULT=PARTIAL — no CLI in $BIN_DIR; brew install llama.cpp for CLI engine"
fi

echo "LensTrans Mac finds CLI via PATH / Homebrew / third_party/llama.cpp/build/bin"
echo "Metal in-process link in SPM App remains UNIMPLEMENTED (see mac/UNIMPLEMENTED.md)"
