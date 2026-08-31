# macOS（SPM）

```bash
cd mac
swift test                              # LogicTests
swift build -c release --product LensTrans   # 有 third_party libllama 时链 Metal 进程内
bash ../tools/eval/mac-smoke.sh         # 本机门禁（含 e2e）
./.build/release/LensTrans              # 托盘 LT（accessory）
./.build/release/LensTrans --no-onboard # 跳过首次引导
./.build/release/LensTrans --e2e --e2e-llama --no-onboard
```

本地引擎：**进程内 Metal**（`Native/LlamaBridge`）优先；失败再 spawn `llama-completion`。

## 一键本地跑（推荐）

```bash
# 断点续传拉 GGUF → release 构建 → 打 .app（默认内置 GGUF）→ 托盘启动
bash tools/run/run-mac.sh
bash tools/run/run-mac.sh --e2e          # 自动门禁
bash tools/run/run-mac.sh --fetch-llama  # 额外构建 third_party llama.cpp b10688
```

## 模型 / llama.cpp

```bash
bash tools/fetch/fetch-gguf.sh                    # → models/（gitignore，不进 git）
bash tools/fetch/fetch-llama-cpp.sh               # Metal 库 + CLI；钉 b10688
# 或: brew install llama.cpp   # 仅 CLI 回退
```

运行时模型路径优先 **`.app/Contents/Resources/models/`**（打包内置），再设置路径 / Application Support / 仓库 `models/`。

## 打包 / 安装

```bash
bash tools/pack/pack-mac.sh                 # 默认：内置 GGUF → dist/macos/（≤520MB）
bash tools/pack/pack-mac.sh --offline       # 同上（别名）
bash tools/pack/pack-mac.sh --base          # 瘦身包无 GGUF → dist/macos-base/
bash tools/pack/install-mac.sh --user       # → ~/Applications（默认含模型）
bash tools/pack/install-mac.sh --base --user
```

可选签名（本机有 Developer ID 时）：

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash tools/pack/pack-mac.sh --sign
# 公证需另配 notarytool；脚本默认不做公证
```

状态与缺口见 `UNIMPLEMENTED.md` / `docs/mac-dev-status.md`。

约束与 Windows 相同：无 Electron/Tauri；云端不预填网关；默认 Qwen2.5-0.5B Q4_K_M；呈现禁止半透明叠字。
