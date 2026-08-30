# macOS 开发与本机验证说明

## 项目目录

```bash
cd ~/works/LensTrans/lenstrans/mac
```

## 本机已跑通（2026-08-31，Darwin arm64 / Swift 6.3.3）

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| `swift test`（LogicTests 8/8） | PASS | `bash tools/eval/mac-smoke.sh` |
| `swift build -c release` | PASS | `mac/.build/release/LensTrans` |
| Vision OCR smoke | PASS | `swift tools/eval/mac-ocr-smoke.swift` → `Hello LensTrans OCR` |
| GGUF size + SHA256 | PASS | 491400032 / `74a4da8c…` |
| `llama-completion` 本地翻译 | PASS | `tools/eval/out/mac-local-cli-smoke.txt`（ChatML + `-no-cnv`） |
| Capture→OCR→Engine→Present | 代码已接 | `mac/Pipeline.swift`；监视态自动跑 |
| 屏幕录制授权后人工 e2e | 待签字 | 系统设置 → 隐私 → 屏幕录制 |
| llama.cpp Metal 进程内 | 未链 | `mac/UNIMPLEMENTED.md` |
| `.app` / 签名 / 公证 / 安装器 | 未做 | 同上 |

## 命令

```bash
cd mac && swift test && swift build -c release --product LensTrans
bash tools/eval/mac-smoke.sh
./mac/.build/release/LensTrans
```

本地翻译：`~/Library/Application Support/LensTrans/models/qwen2.5-0.5b-instruct-q4_k_m.gguf` + `brew install llama.cpp`（用 `llama-completion`，不要用新版对话式 `llama-cli` 做批量）。

不做 Electron / Tauri / Hunyuan。
