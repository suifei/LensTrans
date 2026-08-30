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
| `swift build -c release` | PASS | `mac/.build/release/LensTrans` |
| GGUF size+SHA | PASS | `fetch-gguf.sh` → 491400032 / `74a4da8c…` |
| llama.cpp b10688 + Metal 库/CLI | PASS | `fetch-llama-cpp.sh`（GitHub 走代理）→ `build/bin/llama-completion` |
| e2e（合成帧 + 本地翻译） | PASS | `tools/eval/mac-e2e.sh` |
| `.app` 基础包 / `--e2e` | PASS | `pack-mac.sh` → `dist/macos/` |
| 离线包（含 GGUF ≤520MB） | PASS | `pack-mac.sh --offline` |
| 一键运行 | PASS | `tools/run/run-mac.sh` |
| SCKit 真机 | soft SKIP | 需屏幕录制授权 |
| Metal 进程内链入 App | 未做 | `mac/UNIMPLEMENTED.md` |
| Developer ID / 公证 | 未做 | `pack-mac.sh --sign` 预留 |

## 命令

```bash
bash tools/fetch/fetch-gguf.sh --to-app-support          # ModelScope
bash tools/fetch/fetch-llama-cpp.sh                      # GitHub via 127.0.0.1:8080
cd mac && swift test && swift build -c release --product LensTrans
bash tools/pack/pack-mac.sh
bash tools/pack/pack-mac.sh --offline
bash tools/eval/mac-e2e.sh && bash tools/eval/mac-e2e.sh --app
bash tools/run/run-mac.sh
bash tools/pack/install-mac.sh --user
```

不做 Electron / Tauri / Hunyuan。
