# macOS 实现状态（相对 Windows 全链路）

本 Cloud/Linux 宿主 **不能** 编译 AppKit / ScreenCaptureKit；真机验收需在 macOS 12.3+（建议 13+）上执行：

```bash
cd ~/works/LensTrans/mac   # 或仓库 mac/
swift test                 # LensTransLogic 纯逻辑
swift build -c release     # 需 Apple SDK；Linux 上 executable 目标会失败属预期
```

无 Electron / Tauri。CMake 不混编 Swift。

| 文件 | 对等 Windows | 状态 |
| --- | --- | --- |
| `App.swift` | `wWinMain` / `Run` | 入口 + 托盘/热键/引导接线 |
| `OverlayPanel.swift` | overlay HWND + 穿透 | NSPanel 编辑/穿透/多框 registry + present 绘制 |
| `Capture.swift` | WGC + BitBlt + PrintWindow | ScreenCaptureKit 实现（需 Mac 编测） |
| `Ocr.swift` | Windows.Media.OCR | Vision → MacOcrBlock（需 Mac 编测） |
| `Present.swift` | `present.hpp` | 决策 + AA + 绘制；纯逻辑见 `Logic/` |
| `Engine.swift` | `engine_local` / `engine_cloud` | 云端 URLSession 已接；本地 Metal 待链 llama.cpp |
| `Tray.swift` | `Shell_NotifyIcon` | 完整菜单树（引擎/语言/模式/自启/设置/缓存） |
| `Settings.swift` | 设置 5 Tab | NSTabView 已实现；密钥走 Keychain |
| `Onboarding.swift` | 640×420 三步引导 | 已实现；**禁止为探测启动 SCStream**；可后台下 GGUF |
| `Hotkeys.swift` | `RegisterHotKey` | Carbon EventHotKey 注册 |
| `Secrets.swift` | DPAPI + HKCU Run | Keychain + SMAppService/LaunchAgent |
| `Logic/PureLogic.swift` | core present/router/cloud parse | 可在无 Cocoa 环境 `swift test` |
| `Package.swift` | — | SPM：Logic 库 + App + Tests |

| PRD 项 | 状态 | 对应 Windows |
| --- | --- | --- |
| NSPanel 穿透/编辑 | 已实现代码 | overlay + Ctrl+E |
| ScreenCaptureKit | 已实现代码，待 Mac 真机 | WGC + PrintWindow |
| Vision OCR → OcrBlock | 已实现代码，待 Mac 真机 | Windows.Media.OCR |
| llama.cpp + Metal | **未链**（接口+错误路径） | 进程内 llama.cpp b10688 |
| 云端 OpenAI 兼容 | URLSession 已接 | WinHTTP + DPAPI |
| 托盘 NSStatusItem | 已接 | 托盘完整树 |
| 设置 5 Tab | 已接 | Win32 Tab + 热键录入 |
| 3 步引导 + 屏幕录制权限 | 已接（预检不启流） | 640×420 引导 |
| 多框 / 热键 | OverlayBoxStore + HotkeyCenter | 多 HWND + RegisterHotKey |
| 沉浸替换 / 贴条 | Present 绘制已接 | 框内填充+贴条 |
| 开机自启双向同步 | SMAppService/LaunchAgent | HKCU Run |
| 安装器 | **未做** | `tools/pack/pack-windows.ps1` |
| 本地 Metal 推理 | **未做** | LENSTRANS_WITH_LLAMA |

## 仍需 Mac 真机才能关闭的项

1. Xcode / `swift build` App 目标（ScreenCaptureKit、Vision、AppKit）
2. 屏幕录制授权后的 Capture→OCR→Present 端到端
3. llama.cpp Metal 链接与 WS 采样
4. 签名 / 公证 / 安装器

不做：Electron / Tauri / 跨平台 UI 壳。
