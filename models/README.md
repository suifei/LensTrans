# models

GGUF weights are **not** stored in git.

Default local engine: official **Qwen2.5-0.5B Instruct Q4_K_M** (`Apache-2.0`).

| | |
| --- | --- |
| file | `qwen2.5-0.5b-instruct-q4_k_m.gguf` |
| bytes | `491400032` |
| SHA256 | `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db` |

Place the file in this directory. ModelScope first, Hugging Face as fallback:

```bat
curl.exe -L -C - --retry 8 --retry-all-errors -o models\qwen2.5-0.5b-instruct-q4_k_m.gguf "https://www.modelscope.cn/models/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/master/qwen2.5-0.5b-instruct-q4_k_m.gguf"
```

```bat
curl.exe -L -C - --retry 8 --retry-all-errors -o models\qwen2.5-0.5b-instruct-q4_k_m.gguf "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"
```

Verify size and hash before running. The model LICENSE copy used for product review lives in `tools/eval/licenses/`.
