# LensTrans

[中文](../../README.md) · **English** · [日本語](README.ja.md) · [한국어](README.ko.md)

A **native Windows live screen translator**. Draw a layered, click-through box over any window; LensTrans captures pixels with Windows Graphics Capture (WGC), reads them with system OCR, translates locally (Qwen2.5-0.5B) or through a **user-supplied** OpenAI-compatible endpoint, and covers the source with immersive fill or a sticker. No Electron, no Tauri, no WebView shell.

## What it is

On-screen text is pixels, not a DOM. LensTrans does not inject hooks or read another process's private memory. It captures only the pixels inside its own boxes, OCRs them, and paints the translation on the same rectangle.

```
  ┌─ other app ──────────────────────────────────────────┐
  │  File   Edit   View                                  │
  │                                                      │
  │    ┌─ LensTrans box (Watching, click-through) ────┐  │
  │    │                                              │  │
  │    │   Settings          →    设置                │  │
  │    │   Cancel            →    取消                │  │
  │    │   Please wait…      →    请稍等              │  │
  │    │                                              │  │
  │    └──────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────┘
         tray  ·  Ctrl+E edit / passthrough  ·  Esc quit
```

The box is a `WS_POPUP` layered HWND (`WS_EX_LAYERED | TOPMOST | TOOLWINDOW`) with no taskbar entry. In **Watching** it sets `WS_EX_TRANSPARENT` so clicks reach the window underneath. In **Editing** it clears passthrough; you drag the title bar and resize with eight 12 px handles. Multiple boxes are supported, each with its own state machine:

```
Hidden → Editing → Watching ⇄ Translating
              Paused ← any state (hotkey; capture stops, overlay keeps the last frame)
```

Presentation is two honest modes: fill the glyph rectangle with the sampled background majority color and write the translation (immersive), or cover the source with an opaque sticker. Semi-transparent ghost text on top of the original is a bug. Contrast mode is a sticker plus the source at 60% size underneath — not stacked glyphs. If the glyph color fails WCAG AA 4.5:1 against the fill, it is inverted against that fill.

There are no product screenshots in this repository. The diagram above is structural so we do not hang a fake image URL.

Most screen translators grab a bitmap and open a **separate result window**. LensTrans stays on the region: **pin the box, follow the pixels, cover the source**.

| | Typical popup tool | LensTrans |
| --- | --- | --- |
| Where | A second window, away from the source | A frame pinned to the pixels you drew |
| When | One-shot hotkey | Updates as the box contents change |
| Offline | Often needs the network | Default local Qwen2.5-0.5B |
| How it looks | Source and translation both visible | Immersive fill or a sticker **covering** the source |

## Features

| Area | What ships on Windows |
| --- | --- |
| Overlay | Multi-box, topmost, edit / click-through, full tray menu |
| Capture | WGC (window session / monitor crop); GDI `BitBlt` / `PrintWindow` fallback |
| Change detect | 1/4 downsample + 8×8 SSD; idle sleep after ~2 s of no DIFF so CPU does not spin |
| OCR | `Windows.Media.OCR` on an STA thread → unified `OcrBlock` (text, bbox, sampled color) |
| Stabilize | Two matching frames (bbox+text) plus 300 ms debounce before commit |
| Present | Immersive replace / sticker (~92% opaque) / sticker + contrast. Pure transparent overlay text is forbidden |
| Local engine | Qwen2.5-0.5B Instruct Q4_K_M via [llama.cpp](https://github.com/ggml-org/llama.cpp) **b10688** (in-process link or `llama-cli`) |
| Cloud engine | WinHTTP `POST {base}/chat/completions`. Base URL / model / API key all **empty**; empty disables cloud |
| Secrets | DPAPI on disk; settings serialization must not contain `api_key` (unit-tested) |
| UI | 5-tab settings, 3-step first-run (does not start WGC during onboarding) |
| Hotkeys | `Ctrl+E` edit/passthrough · `Ctrl+Shift+L` new box · `Ctrl+T` pause · `Ctrl+Shift+H` hide · `Ctrl+,` settings |

## Quick start

Requires Windows 10 21H2+ or Windows 11, x64, Visual Studio 2022, and a Windows 10/11 SDK.

1. Clone this repo. Fetch llama.cpp **b10688** per [Build](#build), and the GGUF per [models/README.md](../../models/README.md).
2. Build `lenstrans_overlay` and run `build\Release\lenstrans_overlay.exe`.
3. Allow **screen recording** if Windows asks. Draw a box over English UI. `Ctrl+E` to click through to the window underneath.
4. Optional cloud: open Settings and paste *your* Base URL, model id, and key. Nothing is pre-filled.

A scripted zip (not Inno / NSIS / a store-signed package) is documented in [docs/installer.md](../installer.md). There is no production-signed MSIX in this tree.

## Build

```bat
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

In-process llama.cpp (required for the local engine inside the overlay):

```bat
git clone --depth 1 --branch b10688 https://github.com/ggml-org/llama.cpp.git third_party\llama.cpp
```

Build that tree **Release x64**, then reconfigure LensTrans. CMake turns on `LENSTRANS_WITH_LLAMA=ON` when it finds `third_party/llama.cpp/build/src/Release/llama.lib`. Pin details: [third_party/README.md](../../third_party/README.md).

```
tag:    b10688
commit: c589f0ed10c643678c4707dd160c21ac7633ebc0
remote: https://github.com/ggml-org/llama.cpp.git
```

Ninja + MSVC also works. Do not add vcpkg, and do not replace the UI with a cross-platform shell.

### Tests

| Target | Role |
| --- | --- |
| `lenstrans_test` | Core: cache, router, present, settings; injected-frame pipeline (no WGC) |
| `lenstrans_test_hotkey` | Default four `RegisterHotKey` bindings |
| `lenstrans_test_llama` | Optional; needs the GGUF (`--quality-10`, `--quality-30`, `--flores50`) |
| `lenstrans_e2e_target` | Fixture HWND (white `HELLO Settings`) for overlay scripts |
| `lenstrans_wgc_probe` | WGC permission + OCR smoke |

PowerShell helpers live in `tools/eval/` (they write reports under `tools/eval/out/`, gitignored). See [tests/README.md](../../tests/README.md).

### Packaging

```bat
powershell -File tools\pack\pack-windows.ps1
powershell -File tools\pack\pack-windows.ps1 -Offline
powershell -File tools\pack\install-windows.ps1
```

The base pack does not include the GGUF. The offline pack is base + `models/*.gguf`. The script fails if a size cap is exceeded. Install lands in `%LOCALAPPDATA%\LensTrans\app` by default; it does not write keys, and it does not copy a GGUF unless you built the offline pack.

## Size and memory (product budgets)

These are the numbers the project is held to — not marketing claims. Acceptance uses **Working Set (WS)**, not Private Bytes reported as “peak memory”.

| Budget | Limit | Notes |
| --- | --- | --- |
| Base pack | **≤ 30 MB** | Overlay + llama/ggml DLLs; **no** GGUF |
| Offline pack | **≤ 520 MB** | Base + official Q4_K_M (~491 MB) + installer headroom |
| Inference peak | **WS ≤ 550 MB** | Includes GGUF mmap |
| Local idle resident | ≤ 600 MB (typical ~520 MB) | After the Q4_K_M lock-in |
| Main process, no model | ≤ 80 MB | Overlay without weights |
| Cloud resident | ≤ 120 MB | Cloud engine only |
| First token (≤100 chars, warm, greedy) | ≤ 800 ms | Target on a modern CPU; not a published SLO |

A local measurement of the scripted base tree was about **4.5 MB** uncompressed / **1.8 MB** zip, offline total about **496 MB** — under the caps. That is one machine’s artifact; toolchains change the number, the budget does not.

Default weights: `qwen2.5-0.5b-instruct-q4_k_m.gguf`, 491400032 bytes, SHA256 `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`. Download steps: [models/README.md](../../models/README.md). It is the default because **Apache-2.0 allows redistribution including EU/UK/KR**, not because 0.5B already matches a dedicated MT model.

## Privacy

- **Default path is local.** Pixels stay on the machine; OCR is `Windows.Media.OCR`; translation is llama.cpp + the GGUF you downloaded.
- **No baked-in cloud gateway.** Source does not ship a default Base URL, model name, or API key. Cloud is off until all three fields are set, plus a “test connection” action.
- The key is stored with **DPAPI**, not in the settings file. Settings serialization is tested to omit `api_key`.
- Capture uses system APIs (WGC / GDI). No injection into other processes, no reading foreign private memory.
- Git blocks `*.gguf`, `*.pfx`, `dist/*.cer`, the whole `third_party/llama.cpp` tree, `build/`, `.cache/`, `.env`, and secret-like files. Do not push them.

## Platform

| | Status |
| --- | --- |
| **Windows 10/11 x64** | Native C++20 + Win32. This is the product. |
| **macOS** | Swift AppKit **interface stubs** under `mac/` — see [mac/UNIMPLEMENTED.md](../../mac/UNIMPLEMENTED.md). ScreenCaptureKit / Vision / Metal are not wired. No Xcode project in this repo. Windows is finished first. |

## Limitations (read this)

- The default local model is **0.5B**. Short UI strings often come out usable; long sentences and idioms frequently go literal or scramble. That is a capacity limit, not “tune the prompt and it becomes dedicated MT”. Formal FLORES / COMET acceptance is still open.
- Production / Store code signing is not in this repository. The test-sign path in `tools/pack/pack-msix.ps1` stays on the local machine; certificates are not committed.
- macOS is not a shipping build.
- Hunyuan / HY-MT community licenses exclude EU/UK/KR. They are **not** the default engine and do not go into the installer.

## Layout

```
core/           shared C++: OcrBlock, frame diff, local/cloud engines, present, pipeline, settings
win/            overlay, WGC capture, WinRT OCR, tray/settings, DPAPI
mac/            Swift stubs (not compiled on Windows)
tests/          unit + e2e fixture + WGC probe
tools/pack/     zip / MSIX scripts
tools/eval/     probes and quality scripts (out/ gitignored)
docs/           installer + M0 notes
models/         GGUF goes here (weights gitignored)
third_party/    clone llama.cpp b10688 here (tree gitignored)
```

Module map and hard constraints: [docs/M0-poc-structure.md](../M0-poc-structure.md). Model license and eval plan: [docs/M0-model-eval.md](../M0-model-eval.md).

## License

[MIT](../../LICENSE) © 2026 flynn (suifei).

The optional Qwen2.5-0.5B GGUF is **Apache-2.0** (Alibaba Cloud). You must keep that license with any redistributed weights. Review copy: `tools/eval/licenses/`. llama.cpp has its own license; clone it from upstream.

## Contributing

Issues and PRs that match the native-Windows design are welcome.

- Keep the UI on Win32 / AppKit. Do not introduce Electron, Tauri, Qt, Flutter, or WebView as the shell.
- Do not add a default cloud host, sample API key, or gateway constant.
- Do not commit `*.gguf`, `*.pfx`, `dist/*.cer`, `third_party/llama.cpp`, `build/`, `.cache/`, or secrets.
- Present path: if the source is still visible under translucent translated glyphs, that is a regression.
- Run `lenstrans_test` before sending a core change.

Do not bump the llama.cpp commit mid-eval. The pin is in [third_party/README.md](../../third_party/README.md).
