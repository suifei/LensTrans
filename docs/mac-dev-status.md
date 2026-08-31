# macOS 开发与本机验证说明

## 项目目录

```bash
cd ~/works/LensTrans/lenstrans/mac
```

## 网络策略

| 场景 | 策略 |
| --- | --- |
| GitHub（llama.cpp clone 等） | **优先**本机代理 `http://127.0.0.1:8080`（`tools/fetch/_proxy.sh`） |
| GGUF | **ModelScope 国内源**；不依赖 HF 直连（脚本内 HF 仅代理末路） |

## 本机已跑通（2026-08-31，Darwin arm64）

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test` | PASS | LogicTests 8/8 |
| `swift build -c release` | PASS | `mac/.build/release/LensTrans` 链接 `libllama`/`libggml-metal` |
| GGUF size+SHA | PASS | `fetch-gguf.sh` → 491400032 / `74a4da8c…`（**不进 git**） |
| llama.cpp b10688 + Metal 库/CLI | PASS | `fetch-llama-cpp.sh` → `build/bin/libllama.dylib` + `llama-completion` |
| **Metal 进程内翻译** | PASS | e2e `translate_backend=metal` / `metal_linked=true` |
| e2e（合成帧 + 本地翻译） | PASS | `.build` 与 `.app` 均 PASS |
| `.app` 默认包（内置 GGUF ≤520MB） | PASS | `pack-mac.sh` → ~516 MB；`Resources/models/*.gguf` |
| `.app` Frameworks dylib | PASS | `Contents/Frameworks/libllama*.dylib` |
| 瘦身包（`--base` 无 GGUF） | 可选 | `pack-mac.sh --base` → `dist/macos-base/` |
| 一键运行 | PASS | `tools/run/run-mac.sh` |
| SCKit 真机 | soft SKIP | 需屏幕录制授权 |
| Developer ID / 公证 | 未做 | `pack-mac.sh --sign` 预留 |

## 命令

```bash
bash tools/fetch/fetch-gguf.sh                           # ModelScope → models/（gitignore）
bash tools/fetch/fetch-llama-cpp.sh                      # GitHub via 127.0.0.1:8080
cd mac && swift test && swift build -c release --product LensTrans
bash tools/pack/pack-mac.sh                              # 默认内置 GGUF
bash tools/pack/pack-mac.sh --base                        # 无 GGUF 瘦身包
bash tools/eval/mac-e2e.sh && bash tools/eval/mac-e2e.sh --app
bash tools/run/run-mac.sh --e2e
bash tools/pack/install-mac.sh --user
```

本地引擎优先级：**进程内 Metal** → `llama-completion` CLI。运行时模型路径优先 **App 内置** `Contents/Resources/models/`。

不做 Electron / Tauri / Hunyuan。
