# macOS 实现状态（相对 Windows 全链路）

本仓库 `mac/` 在 **macOS 13+ / Apple Silicon** 上用 SwiftPM 构建。Linux CI 只跑 `LensTransLogic` 纯逻辑测试。

```bash
cd mac
swift test                 # LogicTests（Linux 亦可）
swift build -c release     # AppKit / ScreenCaptureKit / Vision（需 macOS）
bash ../tools/eval/mac-smoke.sh
```

无 Electron / Tauri。CMake 不混编 Swift。

| 文件 | 对等 Windows | 状态 |
| --- | --- | --- |
| `App.swift` | `wWinMain` / `Run` | 入口 + 托盘/热键/引导接线 |
| `OverlayPanel.swift` | overlay HWND + 穿透 | NSPanel 编辑/穿透/多框 + Present |
| `Pipeline.swift` | overlay 监视循环 | Capture→OCR→Engine→Present 已接 |
| `Capture.swift` | WGC + crop | ScreenCaptureKit（需屏幕录制权限） |
| `Ocr.swift` | Windows.Media.OCR | Vision → MacOcrBlock |
| `Present.swift` | `present.hpp` | 决策 + AA + 绘制；纯逻辑见 `Logic/` |
| `Engine.swift` | `engine_local` / `engine_cloud` | 云端 URLSession；本地 **llama-cli** 回退（Metal 进程内未链） |
| `Tray.swift` | `Shell_NotifyIcon` | 完整菜单树 |
| `Settings.swift` | 设置 5 Tab | NSTabView；密钥 Keychain |
| `Onboarding.swift` | 640×420 三步引导 | **禁止为探测启动 SCStream**；可后台下 GGUF |
| `Hotkeys.swift` | `RegisterHotKey` | Carbon EventHotKey |
| `Secrets.swift` | DPAPI + HKCU Run | Keychain + SMAppService/LaunchAgent |
| `Info.plist` | — | 含 `NSScreenCaptureUsageDescription` |
| `Logic/PureLogic.swift` | core present/router/cloud parse | `swift test` |
| `Package.swift` | — | SPM：Logic + App + Tests |

| PRD 项 | 状态 | 对应 Windows |
| --- | --- | --- |
| NSPanel 穿透/编辑 | 已实现 | overlay + Ctrl+E |
| ScreenCaptureKit | 已实现；首次抓屏需用户授权 | WGC |
| Vision OCR → OcrBlock | 已实现 | Windows.Media.OCR |
| llama.cpp + Metal 进程内 | **未链**（SPM 无 Xcode Metal target） | 进程内 llama.cpp |
| llama-cli 本地回退 | **已接**（Homebrew / PATH / third_party） | Win CliEngine |
| 云端 OpenAI 兼容 | URLSession 已接 | WinHTTP + DPAPI |
| 托盘 / 设置 / 引导 / 热键 / 多框 | 已接 | 对等 |
| 沉浸替换 / 贴条 | Present + Pipeline 已接 | 框内填充+贴条 |
| 开机自启 | SMAppService/LaunchAgent | HKCU Run |
| 安装器 / 签名 / 公证 | **未做** | `tools/pack/pack-windows.ps1` |

## 本机已验证（见 `docs/mac-dev-status.md` / `tools/eval/out/`）

- `swift test`、`swift build -c release`
- `tools/eval/mac-smoke.sh`

## 仍明确未完成

1. llama.cpp **Metal 进程内**链接与 WS 采样签字
2. 屏幕录制授权后的人工 e2e 签字（拉框 → 译文覆盖）
3. `.app` 打包、签名、公证、安装器

不做：Electron / Tauri / 跨平台 UI 壳。
