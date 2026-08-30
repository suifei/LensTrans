# macOS 未实现清单（Windows 优先做满）

本机是 Windows。下列 Swift **未在本机编译**，不要当成已编过。CMake 不混编 Swift。无 Electron / Tauri。

| 文件 | 对等 Windows | 状态 |
| --- | --- | --- |
| `App.swift` | `wWinMain` / `Run` | 入口骨架，未编 |
| `OverlayPanel.swift` | overlay HWND + 穿透 | 接口桩（ignoresMouseEvents） |
| `Capture.swift` | WGC + BitBlt + PrintWindow | 未实现（ScreenCaptureKit 抛 unimplemented） |
| `Ocr.swift` | Windows.Media.OCR | 字段已对齐，未跑 Vision |
| `Present.swift` | `present.hpp` 沉浸/贴条/淡出 | 决策函数已写，未接绘制 |
| `Engine.swift` | `engine_local` / `engine_cloud` | 接口桩，未接 Metal / URLSession |
| `Tray.swift` | `Shell_NotifyIcon` 菜单树 | 菜单项骨架，action 未接 |
| `Settings.swift` | 设置 5 Tab | `present()` 空；云端不预填 |
| `Onboarding.swift` | 640×420 三步引导 | 文案步骤已标；**禁止为探测启动 SCStream** |
| `Hotkeys.swift` | `RegisterHotKey` + 点击录入 | Carbon 常量已列，未注册 |
| `Secrets.swift` | DPAPI + HKCU Run | Keychain / 登录项未接 |

| PRD 项 | 状态 | 对应 Windows |
| --- | --- | --- |
| NSPanel 穿透/编辑 | 接口桩 | overlay + Ctrl+E |
| ScreenCaptureKit | 未实现 | WGC + PrintWindow |
| Vision OCR → OcrBlock | 字段已对齐，未跑 | Windows.Media.OCR |
| llama.cpp + Metal | 未接 | 进程内 llama.cpp b10688 |
| 云端 OpenAI 兼容 | 未接 | WinHTTP + DPAPI |
| 托盘 NSStatusItem | 菜单骨架，未接逻辑 | 托盘完整树 |
| 设置 5 Tab | 未做窗口 | Win32 Tab + 热键录入 |
| 3 步引导 + 屏幕录制权限 | 步骤说明已写，无窗口 | 640×420 引导（不发起 WGC） |
| 多框 / 热键 | 未做 | 多 HWND + RegisterHotKey |
| 沉浸替换 / 贴条 | 决策桩，未画 | 框内填充+贴条 |
| 开机自启双向同步 | 未做 | HKCU Run 读/写/删 |
| 安装器 | 未做 | `tools/pack/pack-windows.ps1` |

不做：Electron / Tauri / 跨平台 UI 壳。Xcode 工程仍待后续在 Mac 上建。
