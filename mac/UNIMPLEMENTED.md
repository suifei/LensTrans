# macOS 实现状态（相对 Windows 全链路）

本仓库 `mac/` 在 **macOS 13+ / Apple Silicon** 上用 SwiftPM 构建。Linux CI 只跑 `LensTransLogic` 纯逻辑测试。

```bash
cd mac
swift test && swift build -c release
bash ../tools/fetch/fetch-gguf.sh          # 仅打包时需要本地 models/（gitignore）
bash ../tools/fetch/fetch-llama-cpp.sh     # Metal 库 → third_party/.../build/bin
bash ../tools/pack/pack-mac.sh             # 默认内置 GGUF → dist/macos/
bash ../tools/run/run-mac.sh --e2e
```

无 Electron / Tauri。CMake 不混编 Swift。

| 文件 | 对等 Windows | 状态 |
| --- | --- | --- |
| `App.swift` | `wWinMain` / `Run` | 入口 + 托盘/热键/引导；`--no-onboard` / `--e2e` |
| `OverlayPanel.swift` | overlay HWND + 穿透 | NSPanel 编辑/穿透/多框 + Present |
| `Pipeline.swift` | overlay 监视循环 | Capture→OCR→Engine→Present；**优先 App 内置** `Resources/models` |
| `Capture.swift` | WGC + crop | ScreenCaptureKit（需屏幕录制权限） |
| `Ocr.swift` | Windows.Media.OCR | Vision → MacOcrBlock |
| `Present.swift` | `present.hpp` | 决策 + AA + 绘制；纯逻辑见 `Logic/` |
| `Engine.swift` | `engine_local` / `engine_cloud` | 云端 URLSession；本地 **优先进程内 Metal**（`LlamaBridge`），失败回退 CLI |
| `Native/LlamaBridge.*` | `LENSTRANS_WITH_LLAMA` | C API 桥接 third_party llama.cpp Metal |
| `Tray.swift` | `Shell_NotifyIcon` | 完整菜单树 |
| `Settings.swift` | 设置 5 Tab | NSTabView；密钥 Keychain |
| `Onboarding.swift` | 640×420 三步引导 | **禁止为探测启动 SCStream**；Range+SHA 下 GGUF |
| `Hotkeys.swift` | `RegisterHotKey` | Carbon EventHotKey |
| `Secrets.swift` | DPAPI + HKCU Run | Keychain + SMAppService/LaunchAgent |
| `Info.plist` | — | `NSScreenCaptureUsageDescription` + `LSUIElement`；打入 `.app` |
| `Logic/PureLogic.swift` | core present/router/cloud parse | `swift test` |
| `Package.swift` | — | SPM：Logic + LlamaBridge + App + Tests |

| PRD 项 | 状态 | 对应 Windows |
| --- | --- | --- |
| NSPanel 穿透/编辑 | 已实现 | overlay + Ctrl+E |
| ScreenCaptureKit | 已实现；首次抓屏需用户授权 | WGC |
| Vision OCR → OcrBlock | 已实现 | Windows.Media.OCR |
| llama.cpp + Metal 进程内 | **已接**（有 `libllama.dylib` 时 `LENSTRANS_WITH_LLAMA`） | 进程内 llama.cpp |
| llama-cli 本地回退 | **已接**（`llama-completion` / PATH / third_party / `.app` Resources/bin） | Win CliEngine |
| GGUF 下载 | **已接**（引导内 + `tools/fetch/fetch-gguf.sh`）；**打包默认内置**（不进 git） | model_download.cpp |
| 云端 OpenAI 兼容 | URLSession 已接 | WinHTTP + DPAPI |
| 托盘 / 设置 / 引导 / 热键 / 多框 | 已接 | 对等 |
| `.app` 默认包（内置 GGUF） | **已做** `pack-mac.sh` → `dist/macos/`（≤520MB） | offline |
| `.app` 瘦身包（无 GGUF） | **已做** `pack-mac.sh --base` → `dist/macos-base/` | base |
| 本地安装 | **已做** `install-mac.sh` / `--base` | `install-windows.ps1` |
| 一键运行 | **已做** `tools/run/run-mac.sh` | — |
| Developer ID 签名 / 公证 | **未做**（`--sign` + `CODESIGN_IDENTITY` 预留；默认可 ad-hoc） | MSIX TestSign |

## 本机已验证（见 `docs/mac-dev-status.md`）

- `swift test`、`swift build -c release`、e2e `translate_backend=metal`
- `pack-mac.sh` 默认内置 GGUF + Frameworks dylib；体积 ≤520MB

## 仍明确未完成

1. 正式屏幕录制授权后的 **SCKit** 签字（自动 e2e soft SKIP）
2. **Developer ID 签名 + Apple 公证**
3. （可选）llama.cpp dylib 的 `MACOSX_DEPLOYMENT_TARGET=13.0` 对齐（当前链接有 26.0 告警，可运行）

网络：GitHub 优先 `127.0.0.1:8080`；GGUF 走 ModelScope（见 `tools/fetch/_proxy.sh`）。GGUF **永不提交 git**。

不做：Electron / Tauri / 跨平台 UI 壳。
