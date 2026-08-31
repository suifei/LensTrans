# third_party

This repository does **not** vendor [llama.cpp](https://github.com/ggml-org/llama.cpp) or its build tree.

Locked revision (do not bump during evaluation):

| | |
| --- | --- |
| tag | `b10688` |
| commit | `c589f0ed10c643678c4707dd160c21ac7633ebc0` |
| remote | `https://github.com/ggml-org/llama.cpp.git` |

## Windows (in-process link for overlay)

From the LensTrans repo root:

```bat
git clone --depth 1 --branch b10688 https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp
cmake -S third_party/llama.cpp -B third_party/llama.cpp/build -G "Visual Studio 17 2022" -A x64
cmake --build third_party/llama.cpp/build --config Release --target llama
```

Needed afterwards:

- `third_party/llama.cpp/include/llama.h`
- `third_party/llama.cpp/build/src/Release/llama.lib` (plus ggml libs)
- `third_party/llama.cpp/build/bin/Release/llama.dll` (and `ggml*.dll`)

CMake turns `LENSTRANS_WITH_LLAMA=ON` when those files exist. Forcing the option without `llama.lib` is a hard error, not a silent fallback.

## macOS (in-process Metal + CLI fallback)

SPM App links `libllama` / `libggml*` when present under `third_party/llama.cpp/build/bin`
(`mac/Native/LlamaBridge` + `LENSTRANS_WITH_LLAMA`). Runtime prefers in-process Metal;
`llama-completion` / `llama-cli` remains the fallback.

**Network:** GitHub clone **prefers** local HTTP proxy `http://127.0.0.1:8080` (`tools/fetch/_proxy.sh`). GGUF uses ModelScope — see `models/README.md`. GGUF is **never** committed; `pack-mac.sh` copies it into the `.app` at pack time (default bundled track ≤520 MB).

One-shot helper (clone pin + Metal Release build):

```bash
bash tools/fetch/fetch-llama-cpp.sh
# → third_party/llama.cpp/build/bin/libllama.dylib (+ llama-completion)
```

Manual equivalent (proxy first for GitHub):

```bash
export http_proxy=http://127.0.0.1:8080 https_proxy=http://127.0.0.1:8080
git -c http.version=HTTP/1.1 clone --depth 1 --branch b10688 \
  https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp
unset http_proxy https_proxy
cmake -S third_party/llama.cpp -B third_party/llama.cpp/build \
  -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON -DBUILD_SHARED_LIBS=ON \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_EXAMPLES=ON
cmake --build third_party/llama.cpp/build --config Release --target llama-cli
```

Alternatively: `brew install llama.cpp` and ensure `llama-completion` is on `PATH` (CLI fallback only).

`pack-mac.sh` copies Metal dylibs into `LensTrans.app/Contents/Frameworks/` (in-process) and
CLI + dylibs into `Resources/bin/`. Default pack also copies `models/*.gguf` into
`Resources/models/` (from local `models/` or Application Support — not from git).

Qwen weight license copy: [`tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt`](../tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt).
