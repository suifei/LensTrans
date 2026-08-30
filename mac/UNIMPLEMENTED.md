# macOS 实现状态（相对 Windows 全链路）

本仓库 `mac/` 在 **macOS 13+ / Apple Silicon** 上用 SwiftPM 构建。Linux CI 只跑 `LensTransLogic` 纯逻辑测试。

```bash
cd mac
swift test && swift build -c release
bash ../tools/fetch/fetch-gguf.sh --to-app-support
bash ../tools/pack/pack-mac.sh
bash ../tools/run/run-mac.sh --e2e
```

无 Electron / Tauri。CMake 不混编 Swift。

| 文件 | 对等 Windows | 状态 |
| --- | --- | --- |
| `App.swift` | `wWinMain` / `Run` | 入口 + 托盘/热键/引导；`--no-onboard` / `--e2e` |
| `OverlayPanel.swift` | overlay HWND + 穿透 | NSPanel 编辑/穿透/多框 + Present |
| `Pipeline.swift` | overlay 监视循环 | Capture→OCR→Engine→Present；Bundle/Resources 模型与 CLI 解析 |
| `Capture.swift` | WGC + crop | ScreenCaptureKit（需屏幕录制权限） |
| `Ocr.swift` | Windows.Media.OCR | Vision → MacOcrBlock |
| `Present.swift` | `present.hpp` | 决策 + AA + 绘制；纯逻辑见 `Logic/` |
| `Engine.swift` | `engine_local` / `engine_cloud` | 云端 URLSession；本地优先 **llama-completion** / third_party `llama-cli`；Metal 进程内未链 |
| `Tray.swift` | `Shell_NotifyIcon` | 完整菜单树 |
| `Settings.swift` | 设置 5 Tab | NSTabView；密钥 Keychain |
| `Onboarding.swift` | 640×420 三步引导 | **禁止为探测启动 SCStream**；Range+SHA 下 GGUF |
| `Hotkeys.swift` | `RegisterHotKey` | Carbon EventHotKey |
| `Secrets.swift` | DPAPI + HKCU Run | Keychain + SMAppService/LaunchAgent |
| `Info.plist` | — | `NSScreenCaptureUsageDescription` + `LSUIElement`；打入 `.app` |
| `Logic/PureLogic.swift` | core present/router/cloud parse | `swift test` |
| `Package.swift` | — | SPM：Logic + App + Tests |

| PRD 项 | 状态 | 对应 Windows |
| --- | --- | --- |
| NSPanel 穿透/编辑 | 已实现 | overlay + Ctrl+E |
| ScreenCaptureKit | 已实现；首次抓屏需用户授权 | WGC |
| Vision OCR → OcrBlock | 已实现 | Windows.Media.OCR |
| llama.cpp + Metal 进程内 | **未链**（SPM）；`tools/fetch/fetch-llama-cpp.sh` 可构建 b10688 CLI/库 | 进程内 llama.cpp |
| llama-cli 本地回退 | **已接**（`llama-completion` / PATH / third_party / `.app` Resources/bin） | Win CliEngine |
| GGUF 下载 | **已接**（引导内 + `tools/fetch/fetch-gguf.sh` 断点续传+SHA） | model_download.cpp |
| 云端 OpenAI 兼容 | URLSession 已接 | WinHTTP + DPAPI |
| 托盘 / 设置 / 引导 / 热键 / 多框 | 已接 | 对等 |
| `.app` 基础包 | **已做** `pack-mac.sh` → `dist/macos/`（无 GGUF） | `pack-windows.ps1` |
| `.app` 离线包 | **已做** `pack-mac.sh --offline` → `dist/macos-offline/`（含 GGUF，≤520MB） | `-Offline` |
| 本地安装 | **已做** `install-mac.sh` / `--offline` | `install-windows.ps1` |
| 一键运行 | **已做** `tools/run/run-mac.sh` | — |
| Developer ID 签名 / 公证 | **未做**（`--sign` + `CODESIGN_IDENTITY` 预留；默认可 ad-hoc） | MSIX TestSign |

## 本机已验证（见 `docs/mac-dev-status.md`）

- `swift test`、`swift build -c release`、`mac-e2e.sh`、`.app --e2e`
- `fetch-gguf.sh` size/SHA；`pack-mac.sh` base（及可选 offline）

## 仍明确未完成

1. llama.cpp **Metal 进程内**链接与 WS 采样签字（CLI 已可用：`fetch-llama-cpp.sh` → `llama-completion` + Metal dylib；App 仍 spawn CLI）
2. 正式屏幕录制授权后的 **SCKit** 签字（自动 e2e soft）
3. **Developer ID 签名 + Apple 公证**

网络：GitHub 优先 `127.0.0.1:8080`；GGUF 走 ModelScope（见 `tools/fetch/_proxy.sh`）。

不做：Electron / Tauri / 跨平台 UI 壳。
