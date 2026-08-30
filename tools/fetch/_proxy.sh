#!/usr/bin/env bash
# Shared network helpers for tools/fetch/*.sh
#
# Policy (2026-08):
#   - GitHub (clone / release / raw): PREFER local HTTP proxy http://127.0.0.1:8080
#   - GGUF / Hugging Face weights: do NOT rely on HF direct — use ModelScope (domestic)
#   - Proxy is optional fallback for non-GitHub; never a hard dependency for ModelScope
#
# Env:
#   LENSTRANS_HTTP_PROXY  default http://127.0.0.1:8080

: "${LENSTRANS_HTTP_PROXY:=http://127.0.0.1:8080}"

lenstrans_clear_proxy_env() {
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
}

lenstrans_set_proxy_env() {
  export http_proxy="$LENSTRANS_HTTP_PROXY"
  export https_proxy="$LENSTRANS_HTTP_PROXY"
  export HTTP_PROXY="$LENSTRANS_HTTP_PROXY"
  export HTTPS_PROXY="$LENSTRANS_HTTP_PROXY"
}

# GitHub: proxy first, then one direct attempt if proxy fails.
with_github_proxy() {
  if [[ $# -lt 1 ]]; then
    echo "with_github_proxy: missing command" >&2
    return 2
  fi
  echo "--- GitHub via proxy $LENSTRANS_HTTP_PROXY: $* ---"
  lenstrans_set_proxy_env
  if "$@"; then
    lenstrans_clear_proxy_env
    return 0
  fi
  local rc=$?
  echo "proxy failed (exit $rc); retry GitHub direct once ---"
  lenstrans_clear_proxy_env
  if "$@"; then
    return 0
  fi
  rc=$?
  return "$rc"
}

# Domestic / ModelScope: direct first (no proxy required).
with_domestic_direct() {
  if [[ $# -lt 1 ]]; then
    echo "with_domestic_direct: missing command" >&2
    return 2
  fi
  lenstrans_clear_proxy_env
  echo "--- domestic direct: $* ---"
  "$@"
}
