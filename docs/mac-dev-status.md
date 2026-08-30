# macOS 开发与本机验证说明

## 项目目录

```bash
cd ~/works/LensTrans/lenstrans/mac   # 或仓库 mac/
```

## 本机已跑通（2026-08-31，Darwin arm64）

| 检查 | 结果 | 命令/证据 |
| --- | --- | --- |
| `swift test`（LogicTests 8/8） | PASS | `mac/` + `tools/eval/out/mac-smoke-*.txt` |
| `swift build -c release` | PASS | 产出 `mac/.build/release/LensTrans` |
| `mac-logic-verify.py` | PASS | `python3 tools/eval/mac-logic-verify.py` |
| `mac-smoke.sh` | PASS | `bash tools/eval/mac-smoke.sh` |
| Capture→OCR→Engine→Present 代码管线 | 已接线 | `mac/Pipeline.swift`；本地引擎走 `llama-cli` |
| 屏幕录制授权后人工 e2e | 待用户授权后签字 | 系统设置 → 隐私 → 屏幕录制 |
| llama.cpp Metal 进程内 | 未链 | 见 `mac/UNIMPLEMENTED.md` |
| 安装器 / 公证 | 未做 | 同上 |

## 命令

```bash
cd mac && swift test && swift build -c release --product LensTrans
bash tools/eval/mac-smoke.sh
# 运行：
./mac/.build/release/LensTrans
# 托盘 LT → 引导（步骤 2 不启 SCStream）→ 新建框 → Ctrl+E 监视 → 授权屏幕录制
```

本地翻译需要：

1. GGUF：`~/Library/Application Support/LensTrans/models/qwen2.5-0.5b-instruct-q4_k_m.gguf`（引导下载或见 `models/README.md`）
2. `llama-cli`（如 `brew install llama.cpp`）或日后 Metal 进程内链接

不做 Electron / Tauri / Hunyuan。
