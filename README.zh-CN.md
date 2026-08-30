# LensTrans

[English](README.md) · **简体中文** · [日本語](README.ja.md) · [한국어](README.ko.md)

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D4?logo=windows&logoColor=white)](#平台)
[![macOS](https://img.shields.io/badge/macOS-接口桩-lightgrey?logo=apple)](#平台)
[![C++](https://img.shields.io/badge/C%2B%2B-20-00599C?logo=cplusplus)](CMakeLists.txt)
[![UI](https://img.shields.io/badge/shell-Win32%20native-informational)](#它是什么)
[![Engine](https://img.shields.io/badge/local-Qwen2.5--0.5B%20GGUF-orange)](#功能)

**Windows 原生实时屏幕翻译器。** 在任意窗口上拉一个分层、可点击穿透的框：用 Windows Graphics Capture（WGC）抓像素，系统 OCR 读字，本地 Qwen2.5-0.5B 或你自己填的 OpenAI 兼容端点翻译，再用沉浸填色或贴条把原文盖住。不用 Electron，不用 Tauri，不用 WebView 壳。

## 它是什么

屏幕上的字是像素，不是 DOM。LensTrans 不挂钩子、不读别人进程的私有内存，只截自己框里的图，认出字，再在同一矩形上画译文。

```
  ┌─ 被翻译的窗口 ───────────────────────────────────────┐
  │  File   Edit   View                                  │
  │                                                      │
  │    ┌─ LensTrans 框（Watching，点击穿透）──────────┐  │
  │    │                                              │  │
  │    │   Settings          →    设置                │  │
  │    │   Cancel            →    取消                │  │
  │    │   Please wait…      →    请稍等              │  │
  │    │                                              │  │
  │    └──────────────────────────────────────────────┘  │
  └──────────────────────────────────────────────────────┘
         托盘  ·  Ctrl+E 编辑 / 穿透  ·  Esc 退出
```

框是 `WS_POPUP` 分层 HWND（`WS_EX_LAYERED | TOPMOST | TOOLWINDOW`），不占任务栏。**Watching** 打开 `WS_EX_TRANSPARENT`，鼠标落到下层窗口。**Editing** 清掉穿透，可拖顶栏、八向 12px 把手缩放。支持多框，每框自己的状态机：

```
Hidden → Editing → Watching ⇄ Translating
              Paused ← 任意态（热键；停捕获，浮层留最后一帧）
```

呈现只允许两种诚实做法：用背景众数色填矩形再写译文（沉浸），或用不透明贴条盖住原文。禁止「原文还在、半透明字叠上去」。对照模式是贴条下面加 60% 字号原文，不是叠字。字色相对填色低于 WCAG AA 4.5:1 时，字色改成填色反色。

仓库里没有产品截图文件，上面用结构示意，避免挂假图 URL。

多数屏幕翻译是「截一张图 → 另开结果窗」。LensTrans 是 **框住区域 + 跟着像素变 + 盖住原文**：

| | 常见弹窗工具 | LensTrans |
| --- | --- | --- |
| 位置 | 另开一窗，离开原文 | 框钉在你画出的像素上 |
| 时机 | 热键截一次 | 框内画面变化就更新 |
| 离线 | 往往要联网 | 默认本地 Qwen2.5-0.5B |
| 观感 | 原文和译文同时看见 | 沉浸填色或贴条 **盖住** 原文 |

## 功能

| 模块 | Windows 上实际有的 |
| --- | --- |
| 浮层 | 多框、置顶、编辑 / 穿透、托盘完整菜单 |
| 捕获 | WGC（窗口会话 / 监视器裁切）；失败走 GDI `BitBlt` / `PrintWindow` |
| 帧差 | 1/4 下采样 + 8×8 SSD；无 DIFF 约 2 秒后休眠，避免空转吃 CPU |
| OCR | `Windows.Media.OCR` 在 STA 线程 → 统一 `OcrBlock`（文本、框、采样色） |
| 稳定 | 连续 2 帧 bbox+text 一致，再加 300ms 去抖才提交翻译 |
| 呈现 | 沉浸替换 / 贴条（默认约 92% 不透明）/ 贴条+对照。禁止纯透明叠字 |
| 本地翻译 | Qwen2.5-0.5B Instruct Q4_K_M，经 [llama.cpp](https://github.com/ggml-org/llama.cpp) **b10688**（进程内链接或 `llama-cli`） |
| 云端翻译 | WinHTTP `POST {base}/chat/completions`。Base URL / Model / API Key **全部留空**，空则禁用 |
| 密钥 | DPAPI 落盘；设置序列化里不得出现 `api_key`（有单测） |
| 界面 | 设置 5 个 Tab、首次 3 步引导（引导阶段不拉起 WGC） |
| 热键 | `Ctrl+E` 编辑/穿透 · `Ctrl+Shift+L` 新建框 · `Ctrl+T` 暂停 · `Ctrl+Shift+H` 全隐 · `Ctrl+,` 设置 |

## 快速开始

环境：Windows 10 21H2+ 或 Windows 11，x64；Visual Studio 2022 + Windows 10/11 SDK。

1. 克隆本仓库。按 [编译](#编译) 拉 llama.cpp **b10688**，按 [models/README.md](models/README.md) 下载 GGUF。
2. 编出 `lenstrans_overlay`，运行 `build\Release\lenstrans_overlay.exe`。
3. 若弹出屏幕录制权限，点允许。把框拉到英文界面上。`Ctrl+E` 切到穿透后再点下层。
4. 要用云端：打开设置，自己填 Base URL、模型名、Key。源码不预填任何网关。

脚本打包（不是 Inno / NSIS / 商店签名包）见 [docs/installer.md](docs/installer.md)。本树没有可上架的生产签名 MSIX。

## 编译

```bat
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target lenstrans_test lenstrans_overlay
.\build\Release\lenstrans_test.exe
.\build\Release\lenstrans_overlay.exe
```

本地引擎要链 llama.cpp（overlay 进程内推理）：

```bat
git clone --depth 1 --branch b10688 https://github.com/ggml-org/llama.cpp.git third_party\llama.cpp
```

把 llama.cpp 编成 **Release x64**，再重新配置 LensTrans。CMake 若找到 `third_party/llama.cpp/build/src/Release/llama.lib`，会打开 `LENSTRANS_WITH_LLAMA=ON`。锁定说明：[third_party/README.md](third_party/README.md)。

```
tag:    b10688
commit: c589f0ed10c643678c4707dd160c21ac7633ebc0
remote: https://github.com/ggml-org/llama.cpp.git
```

也可用 Ninja + MSVC。不要加 vcpkg，不要把 UI 换成跨平台壳。

### 测试目标

| 目标 | 作用 |
| --- | --- |
| `lenstrans_test` | 核心：缓存、路由、呈现、设置；注入帧全链路（不走 WGC） |
| `lenstrans_test_hotkey` | 默认四键 `RegisterHotKey` |
| `lenstrans_test_llama` | 可选，需要 GGUF（`--quality-10` / `--quality-30` / `--flores50`） |
| `lenstrans_e2e_target` | 独立 HWND 夹具（白底 `HELLO Settings`）给 overlay 脚本用 |
| `lenstrans_wgc_probe` | WGC 权限 + OCR 冒烟 |

`tools/eval/*.ps1` 是验收脚本，报告写到 `tools/eval/out/`（已 gitignore）。说明见 [tests/README.md](tests/README.md)。

### 打包

```bat
powershell -File tools\pack\pack-windows.ps1
powershell -File tools\pack\pack-windows.ps1 -Offline
powershell -File tools\pack\install-windows.ps1
```

基础包不含 GGUF；离线包 = 基础包 + `models/*.gguf`。超过体积上限脚本直接失败。安装默认进 `%LOCALAPPDATA%\LensTrans\app`，不写密钥、不复制 GGUF（除非你打的是离线包）。

## 体积与内存（已拍板口径）

这是产品约束，不是口号。验收看 **Working Set（WS）**，不把 Private Bytes 报成「峰值内存」。

| 口径 | 上限 | 说明 |
| --- | --- | --- |
| 基础包 | **≤ 30 MB** | overlay + llama/ggml DLL，**不含** GGUF |
| 完整离线包 | **≤ 520 MB** | 基础包 + 官方 Q4_K_M（约 491 MB）+ 安装器余量 |
| 推理峰值 | **WS ≤ 550 MB** | 含 GGUF 文件映射 |
| 本地常驻 | ≤ 600 MB（典型约 520 MB） | 锁 Q4_K_M 之后的物理后果 |
| 主进程不含模型 | ≤ 80 MB | 未加载权重 |
| 云端常驻 | ≤ 120 MB | 只走云端时 |
| ≤100 字块首字 | ≤ 800 ms | 现代 CPU、热启动、贪心；不是对外 SLA |

本机曾测过脚本基础树约 **4.5 MB**（zip 约 1.8 MB），离线合计约 **496 MB**，都在上限内。那是单机产物，换工具链数字会变，但预算不变。

默认权重：`qwen2.5-0.5b-instruct-q4_k_m.gguf`，491400032 字节，SHA256 `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`。下载步骤见 [models/README.md](models/README.md)。选它是因为 **Apache-2.0 允许含 EU/UK/KR 的再分发**，不是因为 0.5B 已经达到专职翻译模型的质量。

## 隐私

- **默认本地。** 像素不出机；OCR 用系统引擎；翻译用本机 llama.cpp + 你下载的 GGUF。
- **云端不预填网关。** 源码里没有默认 Base URL、没有示例 Key、没有内置中转。三个字段都填了才启用云端，另有「测试连接」。
- API Key 只走 **DPAPI**，不进明文设置文件。
- 捕获只用系统 API。不做注入，不读其他进程私有内存。
- git 挡住：`*.gguf`、`*.pfx`、`dist/*.cer`、`third_party/llama.cpp` 整树、`build/`、`.cache/`、`.env`、密钥类文件。不要把它们推上来。

## 平台

| | 状态 |
| --- | --- |
| **Windows 10/11 x64** | C++20 + Win32。这是正在做满的产品。 |
| **macOS** | `mac/` 下 Swift AppKit **接口桩**，见 [mac/UNIMPLEMENTED.md](mac/UNIMPLEMENTED.md)。ScreenCaptureKit / Vision / Metal 未接。本仓库无 Xcode 工程。Windows 优先。 |

## 限制（请先读）

- 默认本地模型是 **0.5B**。短 UI 句经常能用；长句、习语容易字面或乱序。这是容量问题，不是「再调一调 prompt 就能当专职 MT」。正式 FLORES / COMET 验收仍开放。
- 本仓库没有生产/商店代码签名。`tools/pack/pack-msix.ps1` 的 test-sign 只在本机，证书不入库。
- macOS 不能当发布包用。
- Hunyuan / HY-MT 因社区许可排除 EU/UK/KR，**不会**作为默认引擎，也不进安装包。

## 目录

```
core/           共享 C++：OcrBlock、帧差、本地/云端引擎、呈现、管线、设置
win/            overlay、WGC 捕获、WinRT OCR、托盘与设置、DPAPI
mac/            Swift 桩（Windows 上不编译）
tests/          单测、e2e 夹具、WGC 探测
tools/pack/     zip / MSIX 脚本
tools/eval/     探测与质量脚本（out/ 不入库）
docs/           安装器说明与 M0 文档
models/         放置 GGUF（权重不入库）
third_party/    自行克隆 llama.cpp b10688（整树不入库）
```

更细的模块表与硬约束清单：[docs/M0-poc-structure.md](docs/M0-poc-structure.md)。模型许可与评测计划：[docs/M0-model-eval.md](docs/M0-model-eval.md)。

## 许可

[MIT](LICENSE) © 2026 flynn (suifei)。

可选的 Qwen2.5-0.5B GGUF 是 **Apache-2.0**（Alibaba Cloud）。再分发权重须附带该协议。核对副本：`tools/eval/licenses/`。llama.cpp 走上游许可证，请从官方仓库克隆。

## 贡献

欢迎符合「原生 Windows 屏幕翻译」方向的 issue 和 PR。

- UI 留在 Win32 / AppKit。不要引入 Electron、Tauri、Qt、Flutter、WebView 当壳。
- 不要增加默认云端 host、示例 API Key、或任何网关常量。
- 不要提交 `*.gguf`、`*.pfx`、`dist/*.cer`、`third_party/llama.cpp`、`build/`、`.cache/`、密钥。
- 呈现路径若出现「原文仍可见、译文半透明叠上」，视为回归。
- 动到 `core/` 请先跑 `lenstrans_test`。

评测中途不要升级 llama.cpp commit。锁定见 [third_party/README.md](third_party/README.md)。
