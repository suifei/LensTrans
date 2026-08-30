# LensTrans

**In-place screen translation. Native overlay. Local by default.**

[English](README.md) · [简体中文](README.zh-CN.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-native-0b57d0)](#build-from-source-windows)
[![macOS](https://img.shields.io/badge/macOS-unimplemented-lightgrey)](mac/UNIMPLEMENTED.md)

Draw a frame over a screen region. OCR it. Cover the source with an opaque fill or a sticker. No Electron, no Tauri, no translucent ghost text stacked on the original.

Windows (Win32) is the working port. macOS is interface stubs only — see [`mac/UNIMPLEMENTED.md`](mac/UNIMPLEMENTED.md).

## Features

- Transparent overlay boxes: edit, resize, multi-box, click-through while watching
- Present modes: immersive replace, sticker, optional contrast. Pure transparent overlay text is forbidden
- Local **Qwen2.5-0.5B Instruct Q4** (Apache-2.0) via llama.cpp **b10688**
- Optional OpenAI-compatible cloud. Base URL, model, and key start empty — no public gateway is prefilled. Keys use DPAPI
- Tray menu, settings (5 tabs), first-run 3-step onboarding, hotkeys
- Two install tracks: base pack **≤30 MB** (download the GGUF on first launch); full offline pack **≤520 MB**

Default hotkeys: `Ctrl+E` edit / click-through · `Ctrl+Shift+L` new box · `Ctrl+T` pause · `Ctrl+Shift+H` hide · `Ctrl+,` settings · `Esc` quit.

There are no product screenshots in-tree. Eval scripts write reports under `tools/eval/out/` (gitignored).

## Install (Windows)

Pack from a Release build (see [docs/installer.md](docs/installer.md)):

```
powershell -File tools/pack/pack-windows.ps1
powershell -File tools/pack/install-windows.ps1
```

Offline pack (needs `models/qwen2.5-0.5b-instruct-q4_k_m.gguf`):

```
powershell -File tools/pack/pack-windows.ps1 -Offline
```

The GGUF is not in git. Download it into `models/` and verify SHA-256 — see [models/README.md](models/README.md).

## Build from source (Windows)

Visual Studio 2022 + Windows 10 SDK, x64. Clone llama.cpp **b10688** first ([third_party/README.md](third_party/README.md)), then:

```
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

In-process llama is on when prebuilt libs exist (`LENSTRANS_WITH_LLAMA`). Allow screen-recording permission if Windows asks.

## macOS

Not a peer of the Windows build. Stubs live under `mac/`. CMake does not compile Swift. Details: [mac/UNIMPLEMENTED.md](mac/UNIMPLEMENTED.md).

## Privacy

Local inference is the default. Cloud runs only after you fill Base URL, model, and key. Source does not embed a gateway host. API keys are stored with DPAPI, never logged.

## License

- Application source: [MIT](LICENSE), Copyright 2026 suifei
- Bundled / downloaded Qwen2.5-0.5B Instruct GGUF: [Apache-2.0](tools/eval/licenses/Qwen2.5-0.5B-Instruct-LICENSE.txt) (Alibaba Cloud)
- llama.cpp (clone yourself): MIT, tag `b10688`

## Contributing and security

Issues and PRs for the Windows path are welcome. Do not commit `*.gguf`, `*.pfx`, `settings.cfg`, or secrets. Do not paste API keys into issues or PRs.

## Docs

- [docs/M0-poc-structure.md](docs/M0-poc-structure.md)
- [docs/installer.md](docs/installer.md)
- [docs/M0-model-eval.md](docs/M0-model-eval.md)
- [tests/README.md](tests/README.md)
