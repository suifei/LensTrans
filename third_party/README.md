# third_party

This repository does **not** vendor [llama.cpp](https://github.com/ggml-org/llama.cpp) or its build tree.

Locked revision (do not bump during evaluation):

| | |
| --- | --- |
| tag | `b10688` |
| commit | `c589f0ed10c643678c4707dd160c21ac7633ebc0` |
| remote | `https://github.com/ggml-org/llama.cpp.git` |

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

Qwen weight license copy: [`tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt`](../tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt).
