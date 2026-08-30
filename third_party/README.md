# third_party

This repository does **not** vendor [llama.cpp](https://github.com/ggml-org/llama.cpp). Clone the locked tag next to this file before building with in-process inference.

Locked revision (do not bump during evaluation):

| | |
| --- | --- |
| tag | `b10688` |
| commit | `c589f0ed10c643678c4707dd160c21ac7633ebc0` |
| remote | `https://github.com/ggml-org/llama.cpp.git` |

```bat
git clone --depth 1 --branch b10688 https://github.com/ggml-org/llama.cpp.git third_party/llama.cpp
```

Then build llama.cpp **Release x64** so these files exist:

- `third_party/llama.cpp/include/llama.h`
- `third_party/llama.cpp/build/src/Release/llama.lib`
- `third_party/llama.cpp/build/bin/Release/llama.dll` (and `ggml*.dll`)

LensTrans links that prebuilt tree when you pass `-DLENSTRANS_WITH_LLAMA=ON` (CMake turns this on automatically if the files above are present).
