# models

GGUF weights are **not** stored in git.

Global fallback: official **Qwen2.5-1.5B Instruct Q4_K_M** (`Apache-2.0`).
LensTrans 0.3.0 also discovers compatible local GGUF files as model plugins.

| | |
| --- | --- |
| file | `qwen2.5-1.5b-instruct-q4_k_m.gguf` |
| bytes | `1117320736` |
| SHA256 | `6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e` |

## Recommended (resume + verify)

**Do not rely on Hugging Face direct.** Prefer ModelScope (domestic).

```bash
# ModelScope first; -C - resume; size+SHA check
bash tools/fetch/fetch-gguf.sh
bash tools/fetch/fetch-gguf.sh --to-app-support   # also ~/Library/Application Support/LensTrans/models/
```

## Manual curl (ModelScope)

```bat
curl.exe -L -C - --retry 8 --retry-all-errors -o models\qwen2.5-1.5b-instruct-q4_k_m.gguf "https://www.modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/master/qwen2.5-1.5b-instruct-q4_k_m.gguf"
```

```bash
curl -L -C - --retry 8 --retry-all-errors -o models/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  "https://www.modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/master/qwen2.5-1.5b-instruct-q4_k_m.gguf"
# verify:
#   stat -f%z models/qwen2.5-1.5b-instruct-q4_k_m.gguf   # 1117320736
#   shasum -a 256 models/qwen2.5-1.5b-instruct-q4_k_m.gguf
```

HF is only a last-resort inside `fetch-gguf.sh` (via local proxy `127.0.0.1:8080`), not a documented primary path.

Verify size and hash before running. The model LICENSE copy used for product review lives in `tools/eval/licenses/`.

## Local model plugins

Place ChatML-compatible instruct GGUF files in one of these directories:

- macOS: `~/Library/Application Support/LensTrans/models/`
- Windows: `%LOCALAPPDATA%\LensTrans\models\`
- packaged app: `Resources/models/` on macOS or `models/` beside the Windows executable

Select a discovered model in macOS Settings, enter its full path in Windows Settings, set
`LENSTRANS_MODEL_PATH`, or write its filename into `active-model.txt` in the same model directory.
Explicit settings and the environment variable take priority. A changed model is preloaded in the
background; Windows applies the change after restart.

The current plugin runtime is llama.cpp. Qwen-family files use the ChatML profile. Official Tencent
`HY-MT1.5-1.8B-GGUF` files use Tencent's unmodified translation/`<source><sn>` formatted prompt and
official sampler; when installed and selected they are the primary translator, with the global Qwen
default used for failed blocks. Tencent's license excludes the EU, UK, and South Korea, so LensTrans
does not redistribute those weights in its public release. Dedicated NLLB, Marian/Bergamot, and
Argos packages need a separate runtime and are not treated as GGUF plugins.

**Packaging:** `bash tools/pack/pack-mac.sh` copies the selected file into
`LensTrans.app/Contents/Resources/models/` (up to 2.2 GB). The GGUF itself stays
gitignored — only the pack script stages it from `models/` or Application Support.

Use `LENSTRANS_GGUF_PATH=/absolute/model.gguf` to build a macOS bundle with a non-default model,
or `-ModelPath C:\path\model.gguf` with `tools/pack/pack-windows.ps1 -Offline`.

Offline Mac pack embeds this file under `LensTrans.app/Contents/Resources/models/` via `bash tools/pack/pack-mac.sh --offline` (not committed to git).
