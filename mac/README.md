# macOS（SPM）

```bash
cd mac
swift test                              # LogicTests
swift build -c release --product LensTrans
bash ../tools/eval/mac-smoke.sh         # 本机门禁（含 e2e）
./.build/release/LensTrans              # 托盘 LT（accessory）
./.build/release/LensTrans --no-onboard # 跳过首次引导
./.build/release/LensTrans --e2e --no-onboard
```

## 一键本地跑（推荐）

```bash
# 断点续传拉 GGUF → release 构建 → 打 .app → 托盘启动（本地引擎）
bash tools/run/run-mac.sh
bash tools/run/run-mac.sh --e2e          # 自动门禁
bash tools/run/run-mac.sh --fetch-llama  # 额外构建 third_party llama.cpp b10688
```

## 模型 / llama.cpp

```bash
bash tools/fetch/fetch-gguf.sh --to-app-support   # models/README.md 锁 size+SHA
bash tools/fetch/fetch-llama-cpp.sh               # third_party/README.md 钉 b10688
# 或: brew install llama.cpp   # 用 llama-completion
```

## 打包 / 安装（双轨）

```bash
bash tools/pack/pack-mac.sh                 # 基础包 dist/macos/LensTrans.app（无 GGUF）
bash tools/pack/pack-mac.sh --offline       # 离线包 dist/macos-offline/（含 Resources/models/*.gguf）
bash tools/pack/install-mac.sh --user       # → ~/Applications
bash tools/pack/install-mac.sh --offline --user
# 或把 .app 拖到 /Applications
```

可选签名（本机有 Developer ID 时）：

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash tools/pack/pack-mac.sh --sign
# 公证需另配 notarytool；脚本默认不做公证
```

状态与缺口见 `UNIMPLEMENTED.md` / `docs/mac-dev-status.md`。

约束与 Windows 相同：无 Electron/Tauri；云端不预填网关；默认 Qwen2.5-0.5B Q4_K_M；呈现禁止半透明叠字。
