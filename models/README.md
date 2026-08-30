# models

GGUF weights are **not** stored in git.

Default local engine: official **Qwen2.5-0.5B Instruct Q4_K_M** (`Apache-2.0`).

| | |
| --- | --- |
| file | `qwen2.5-0.5b-instruct-q4_k_m.gguf` |
| bytes | `491400032` |
| SHA256 | `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db` |

## Recommended (resume + verify)

**Do not rely on Hugging Face direct.** Prefer ModelScope (domestic).

```bash
# ModelScope first; -C - resume; size+SHA check
bash tools/fetch/fetch-gguf.sh
bash tools/fetch/fetch-gguf.sh --to-app-support   # also ~/Library/Application Support/LensTrans/models/
```

## Manual curl (ModelScope)

```bat
curl.exe -L -C - --retry 8 --retry-all-errors -o models\qwen2.5-0.5b-instruct-q4_k_m.gguf "https://www.modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf"
```

```bash
curl -L -C - --retry 8 --retry-all-errors -o models/qwen2.5-0.5b-instruct-q4_k_m.gguf \
  "https://www.modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf"
# verify:
#   stat -f%z models/qwen2.5-0.5b-instruct-q4_k_m.gguf   # 491400032
#   shasum -a 256 models/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

HF is only a last-resort inside `fetch-gguf.sh` (via local proxy `127.0.0.1:8080`), not a documented primary path.

Verify size and hash before running. The model LICENSE copy used for product review lives in `tools/eval/licenses/`.

**Packaging:** `bash tools/pack/pack-mac.sh` copies this file into
`LensTrans.app/Contents/Resources/models/` (default track, ≤520 MB). The GGUF itself stays
gitignored — only the pack script stages it from `models/` or Application Support.

Offline Mac pack embeds this file under `LensTrans.app/Contents/Resources/models/` via `bash tools/pack/pack-mac.sh --offline` (not committed to git).
